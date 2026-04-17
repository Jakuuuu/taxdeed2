# frozen_string_literal: true

# SyncSheetJob — Importa propiedades desde Google Sheets a PostgreSQL
#
# Disparado por:
#   1. Sidekiq-cron: cada 12h (3:00 AM + 3:00 PM ET = "0 7,19 * * *" UTC)
#   2. Admin manual: POST /admin/sync/run_now
#
# 🛡️ BLINDAJE ANTI-ZOMBIE (v3):
#   @sync_log se asigna ANTES de cualquier validación para asegurar que
#   absolutamente CUALQUIER error (incluso falta de credenciales)
#   pueda ser capturado y registrado.
#
# 🚀 MEMORY-SAFE STREAMING (v3):
#   Ya NO carga todas las filas en memoria. Usa GoogleSheetsImporter.fetch_rows_in_chunks
#   que yield lotes de CHUNK_SIZE filas. Cada lote se procesa y se libera antes
#   del siguiente. Incluye GC.start entre lotes y limpieza de cache ActiveRecord.
#   Reduce la huella de memoria de O(N) a O(CHUNK_SIZE).
#
class SyncSheetJob < ApplicationJob
  queue_as :data_sync

  BATCH_SIZE = 200

  retry_on Google::Apis::ServerError, wait: :polynomially_longer, attempts: 3
  retry_on Google::Apis::TransmissionError, wait: :polynomially_longer, attempts: 3

  def perform(sheet_id = nil, sync_log_id = nil)
    # ── 1. Asignar SyncLog ANTES que nada para garantizar el ensure ─────────
    @sync_log = SyncLog.find_by(id: sync_log_id) if sync_log_id.present?

    # ═══════════════════════════════════════════════════════════════════════════
    # 🛡️ BLINDAJE ABSOLUTO: begin / rescue StandardError / ensure
    # ═══════════════════════════════════════════════════════════════════════════
    begin
      @sync_log ||= SyncLog.create!(status: "running", started_at: Time.current)
      @started_at = Time.current

      # ── 2. Validaciones (si fallan, el catch las marca en el SyncLog) ───────
      sheet_id ||= ENV.fetch("GOOGLE_SHEETS_SHEET_ID") {
        Rails.application.credentials.dig(:google_sheets, :sheet_id)
      }
      sheet_id = "mock" if sheet_id.blank? && Rails.env.development?

      raise ArgumentError, "La variable GOOGLE_SHEETS_SHEET_ID o las credenciales no están configuradas." if sheet_id.blank?

      Rails.logger.info "[SyncSheetJob] Iniciando sync de Sheet: #{sheet_id} (log_id: #{@sync_log.id})"

      # ── 3. Extracción STREAMING e importación ────────────────────────────────
      results = stream_and_process(sheet_id)

      refresh_auction_counts
      cleanup_empty_auctions

      # ── 4. Geocodificación fallback ──────────────────────────────────────────
      enqueue_geocoding(@started_at)

      elapsed = (Time.current - @started_at).round(1)
      Rails.logger.info "[SyncSheetJob] Completado en #{elapsed}s. " \
                        "Added: #{results[:added]} | Updated: #{results[:updated]} | " \
                        "Skipped: #{results[:skipped]} | Failed: #{results[:failed]}"

      @sync_log.update!(
        status:           results[:failed] > 0 ? "completed_with_errors" : "success",
        parcels_added:    results[:added],
        parcels_updated:  results[:updated],
        parcels_skipped:  results[:skipped],
        duration_seconds: elapsed,
        completed_at:     Time.current,
        records_synced:   results[:added] + results[:updated],
        records_failed:   results[:failed],
        error_message:    nil
      )

    rescue GoogleSheetsImporter::SheetSchemaError => e
      mark_sync_failed!(e, prefix: "SheetSchemaError")
      raise

    rescue StandardError => e
      mark_sync_failed!(e, prefix: "UnexpectedError")
      raise

    ensure
      # 🛡️ Última línea de defensa
      force_fail_orphaned_log!
    end
  end

  private

  # ═══════════════════════════════════════════════════════════════════════════
  # 🚀 STREAMING PRINCIPAL — Procesa filas chunk por chunk
  #
  # En vez de:
  #   data = GoogleSheetsImporter.fetch_headers_and_rows(sheet_id)  ← OOM!
  #   rows = data[:rows]                                           ← Todo en RAM
  #   process_rows_in_batches(rows)                                ← Demasiado tarde
  #
  # Ahora:
  #   GoogleSheetsImporter.fetch_rows_in_chunks(sheet_id) { |chunk| process(chunk) }
  #   ↑ Solo CHUNK_SIZE filas viven en memoria a la vez
  #
  # IDEMPOTENCIA:
  #   Si Render mata el proceso a mitad de un chunk, las filas ya procesadas
  #   usaron find_or_initialize_by con clave compuesta (state, county, parcel_id)
  #   respaldada por UNIQUE INDEX en PostgreSQL. El siguiente sync simplemente
  #   re-procesa todo sin duplicar — upsert puro.
  # ═══════════════════════════════════════════════════════════════════════════
  def stream_and_process(sheet_id)
    added = 0
    updated = 0
    skipped = 0
    failed = 0

    # Cache de Auctions para evitar N+1 find_or_create_by por cada fila.
    # Key: "state|county|sale_date" → Value: Auction instance.
    # Se limpia entre chunks para no retener memoria indefinidamente.
    @auction_cache = {}

    GoogleSheetsImporter.fetch_rows_in_chunks(sheet_id, chunk_size: BATCH_SIZE) do |chunk, chunk_index|
      chunk_results = process_single_chunk(chunk, chunk_index)

      added   += chunk_results[:added]
      updated += chunk_results[:updated]
      skipped += chunk_results[:skipped]
      failed  += chunk_results[:failed]

      # ── 🧹 LIBERACIÓN AGRESIVA DE MEMORIA ─────────────────────────────────
      # 1. Vaciar la cache de Auctions (se reconstruye si el siguiente chunk
      #    tiene los mismos counties — trade-off aceptable por memoria).
      # 2. Limpiar el identity map de ActiveRecord para liberar objetos Parcel
      #    que ya fueron salvados y no se necesitan más.
      # 3. Forzar GC para devolver memoria al SO inmediatamente.
      @auction_cache.clear
      ActiveRecord::Base.connection.clear_query_cache
      GC.start
    end

    { added: added, updated: updated, skipped: skipped, failed: failed }
  end

  # ── Procesa un chunk individual de filas ──────────────────────────────────
  def process_single_chunk(chunk, chunk_index)
    added = updated = skipped = failed = 0

    chunk.each_with_index do |row, row_in_chunk|
      global_row = (chunk_index * BATCH_SIZE) + row_in_chunk
      result = process_row_with_cache(row)

      case result
      when :added   then added   += 1
      when :updated then updated += 1
      when :skipped then skipped += 1
      end
    rescue ActiveRecord::RecordInvalid => e
      failed += 1
      Rails.logger.warn "[SyncSheetJob] Fila #{global_row + 2} inválida: #{e.message}"
    rescue ActiveRecord::RecordNotSaved => e
      failed += 1
      Rails.logger.error "[SyncSheetJob] Fila #{global_row + 2} bloqueada (CRM immunity?): #{e.message}"
    rescue StandardError => e
      failed += 1
      Rails.logger.error "[SyncSheetJob] Fila #{global_row + 2} falló: #{e.class}: #{e.message}"
    end

    processed_so_far = ((chunk_index + 1) * BATCH_SIZE)
    Rails.logger.info "[SyncSheetJob] Chunk #{chunk_index + 1} completado " \
                      "(+#{added} added, +#{updated} updated, +#{skipped} skipped, +#{failed} failed)"

    { added: added, updated: updated, skipped: skipped, failed: failed }
  end

  # ── Procesamiento con cache de Auctions ───────────────────────────────────
  # En vez de que SheetRowProcessor haga find_or_create_by! por CADA fila,
  # cacheamos el Auction por la key compuesta (state|county|sale_date).
  # Esto reduce las queries de Auction de O(N) a O(unique_auctions).
  def process_row_with_cache(row)
    SheetRowProcessor.process(row, auction_cache: @auction_cache)
  end

  def force_fail_orphaned_log!
    return unless @sync_log&.persisted?

    @sync_log.reload
    return unless @sync_log.running?

    elapsed = (Time.current - (@started_at || @sync_log.started_at || Time.current)).round(1)
    @sync_log.update_columns(
      status:           "failed",
      error_message:    "Job terminated unexpectedly (process killed or out of memory).",
      duration_seconds: elapsed,
      completed_at:     Time.current
    )
    Rails.logger.error "[SyncSheetJob] 🚨 ENSURE: Force-failed orphaned SyncLog ##{@sync_log.id}"
  rescue => e # rubocop:disable Style/RescueStandardError — INTENCIONAL:
    # Este es el último recurso absoluto. Si falla, el SyncLog queda como zombie
    # y solo SyncLog.expire_zombies! puede limpiarlo. Atrapamos TODO (incluyendo
    # Exception) porque prefierimos loguear y sobrevivir a perder el registro.
    Rails.logger.fatal "[SyncSheetJob] 🔥 ENSURE failed: #{e.class}: #{e.message}"
  end

  def mark_sync_failed!(exception, prefix: "Error")
    elapsed = (Time.current - (@started_at || Time.current)).round(1)
    @sync_log&.update!(
      status:           "failed",
      error_message:    "[#{prefix}] #{exception.class}: #{exception.message}",
      duration_seconds: elapsed,
      completed_at:     Time.current,
      records_synced:   0,
      records_failed:   0
    )
    Rails.logger.error "[SyncSheetJob] 🚨 #{prefix}: #{exception.class}: #{exception.message}"
  rescue StandardError => update_error
    Rails.logger.fatal "[SyncSheetJob] 🔥 Could not update SyncLog via update!: #{update_error.message}"
    @sync_log&.update_columns(
      status:        "failed",
      error_message: "[#{prefix}] #{exception.class}: #{exception.message} (update! failed: #{update_error.message})",
      completed_at:  Time.current
    )
  end

  def refresh_auction_counts
    Auction.find_each do |auction|
      auction.update_column(:parcel_count, auction.parcels.count)
    end
    Rails.cache.clear
  rescue StandardError => e
    Rails.logger.error "[SyncSheetJob] Error al actualizar parcel_count: #{e.message}"
  end

  # 🧹 GARBAGE COLLECTOR — Purga Auctions huérfanas (0 parcels)
  # Previene duplicación visual de condados en Rama 1.
  # Seguro: solo elimina auctions sin ninguna parcela asociada.
  def cleanup_empty_auctions
    orphaned = Auction.left_joins(:parcels)
                      .group("auctions.id")
                      .having("COUNT(parcels.id) = 0")
    count = orphaned.count.size
    if count > 0
      orphaned.destroy_all
      Rails.logger.info "[SyncSheetJob] \xF0\x9F\xA7\xB9 Cleaned #{count} empty auction records (0 parcels)"
    end
    count
  rescue StandardError => e
    Rails.logger.error "[SyncSheetJob] Error cleaning empty auctions: #{e.message}"
    0
  end

  def enqueue_geocoding(sync_started_at)
    return unless ENV["REGRID_API_TOKEN"].present?

    synced = Parcel.where("last_synced_at >= ?", sync_started_at)
    with_coords = synced.where.not(latitude: nil).count
    without_coords = synced.where(latitude: nil).pluck(:id)

    return if without_coords.empty?

    GeocodeParcelsBatchJob.perform_later(without_coords)
  rescue StandardError => e
    Rails.logger.warn "[SyncSheetJob] Geocoding enqueue failed (non-fatal): #{e.message}"
  end
end
