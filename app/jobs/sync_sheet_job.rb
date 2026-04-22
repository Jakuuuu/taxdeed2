# frozen_string_literal: true

# SyncSheetJob — Importa propiedades desde Google Sheets a PostgreSQL
#
# Disparado por:
#   1. Sidekiq-cron: cada 12h (3:00 AM + 3:00 PM ET = "0 7,19 * * *" UTC)
#   2. Admin manual: POST /admin/sync/run_now
#   3. Admin manual: POST /admin/sync/run_markets (solo Mercados)
#
# Pipeline de 3 pestañas (selectivo):
#   1. "Propiedades1" → Parcelas + Auctions     ← Default
#   2. "Condados"     → CountyMarketStat         ← Default
#   3. "Mercados"     → RealEstateMonthlyVolume  ← Solo bajo demanda
#
# El parámetro `pipelines` controla qué pestañas sincronizar:
#   - Default (nil o no especificado): [:properties, :counties]
#   - Para Mercados: pipelines: [:markets]
#   - Para todo: pipelines: [:properties, :counties, :markets]
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

  # Error personalizado para abortar sync cuando la memoria está al límite
  class MemoryLimitExceeded < StandardError; end

  BATCH_SIZE = 50

  # Límite de seguridad: si el RSS del proceso supera este valor,
  # abortamos el sync GRACEFULLY antes de que Render nos mate con SIGKILL.
  # Render Starter = 512 MB. Dejamos ~90 MB de headroom.
  MAX_RSS_MB = 420

  retry_on Google::Apis::ServerError, wait: :polynomially_longer, attempts: 3
  retry_on Google::Apis::TransmissionError, wait: :polynomially_longer, attempts: 3

  def perform(sheet_id = nil, sync_log_id = nil, pipelines: nil)
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

      # ── Determinar pipelines a ejecutar ────────────────────────────────────
      # Default: Propiedades + Condados (rápido, ~30s)
      # Mercados se ejecuta SOLO si se solicita explícitamente (denso, ~2-5min)
      active_pipelines = pipelines || [:properties, :counties]
      active_pipelines = active_pipelines.map(&:to_sym)

      Rails.logger.info "[SyncSheetJob] Iniciando sync de Sheet: #{sheet_id} (log_id: #{@sync_log.id}) " \
                        "Pipelines: #{active_pipelines.join(', ')}"

      # ── 3. Pipeline 1: Propiedades (existente) ──────────────────────────────
      results = { added: 0, updated: 0, skipped: 0, failed: 0 }
      if active_pipelines.include?(:properties)
        results = stream_and_process(sheet_id)
        refresh_auction_counts
        cleanup_empty_auctions
      end

      # ── 4. Pipeline 2: Condados (Rama 4) ────────────────────────────────────
      county_results = { added: 0, updated: 0, skipped: 0, failed: 0 }
      if active_pipelines.include?(:counties)
        county_results = stream_and_process_counties(sheet_id)
      end

      # ── 5. Pipeline 3: Mercados (Rama 4) — SOLO bajo demanda ────────────────
      market_results = { added: 0, updated: 0, skipped: 0, failed: 0 }
      if active_pipelines.include?(:markets)
        market_results = stream_and_process_markets(sheet_id)
      end

      # ── 6. Geocodificación fallback ──────────────────────────────────────────
      enqueue_geocoding(@started_at) if active_pipelines.include?(:properties)

      elapsed = (Time.current - @started_at).round(1)
      Rails.logger.info "[SyncSheetJob] Completado en #{elapsed}s. " \
                        "Pipelines: #{active_pipelines.join(', ')} | " \
                        "Parcels — Added: #{results[:added]} | Updated: #{results[:updated]} | " \
                        "Skipped: #{results[:skipped]} | Failed: #{results[:failed]} | " \
                        "Counties: +#{county_results[:added]}/~#{county_results[:updated]} | " \
                        "Markets: +#{market_results[:added]}/~#{market_results[:updated]}"

      total_failed = results[:failed] + county_results[:failed] + market_results[:failed]
      final_status = total_failed > 0 ? "completed_with_errors" : "success"
      error_summary = if total_failed > 0
                        "#{total_failed} row(s) failed validation during import. " \
                        "Parcels: #{results[:failed]}, Counties: #{county_results[:failed]}, " \
                        "Markets: #{market_results[:failed]}. Check application logs."
                      end

      @sync_log.update!(
        status:           final_status,
        parcels_added:    results[:added],
        parcels_updated:  results[:updated],
        parcels_skipped:  results[:skipped],
        duration_seconds: elapsed,
        completed_at:     Time.current,
        records_synced:   results[:added] + results[:updated] +
                          county_results[:added] + county_results[:updated] +
                          market_results[:added] + market_results[:updated],
        records_failed:   total_failed,
        error_message:    error_summary
      )

    rescue MemoryLimitExceeded => e
      # Partial sync completado — los datos YA están en la BD (idempotente).
      # No re-raise: el job terminó su trabajo parcial exitosamente.
      elapsed = (Time.current - (@started_at || Time.current)).round(1)
      @sync_log&.update!(
        status:           "completed_with_errors",
        error_message:    "[MemoryLimit] #{e.message}",
        duration_seconds: elapsed,
        completed_at:     Time.current
      )
      Rails.logger.warn "[SyncSheetJob] ⚠️ Memory limit reached — partial sync saved. Re-run to continue."

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
  # 🚀 STREAMING PRINCIPAL — Procesa filas de Propiedades chunk por chunk
  #
  # 🔗 HYPERLINKS: Pre-extrae las URLs embebidas en celdas del Sheet usando
  #   la API avanzada (spreadsheets.get con fields mask). Luego pasa los
  #   hyperlinks de cada fila al SheetRowProcessor para resolver URLs reales.
  # ═══════════════════════════════════════════════════════════════════════════
  def stream_and_process(sheet_id)
    added = 0
    updated = 0
    skipped = 0
    failed = 0

    # Cache de Auctions para evitar N+1 find_or_create_by por cada fila.
    @auction_cache = {}

    # ── 🔗 Pre-fetch hyperlinks (una sola llamada a la API) ───────────────
    @property_hyperlinks = begin
      GoogleSheetsImporter.fetch_property_hyperlinks(sheet_id)
    rescue => e
      Rails.logger.warn "[SyncSheetJob] ⚠️ No se pudieron extraer hyperlinks de Propiedades: #{e.message}. Continuando sin ellos."
      {}
    end

    # ── 💓 HEARTBEAT INICIAL ──────────────────────────────────────────────
    rss = current_rss_mb
    Rails.logger.info "[SyncSheetJob] 🚀 Startup RSS: #{rss} MB (limit: #{MAX_RSS_MB} MB)"
    if @sync_log&.persisted?
      @sync_log.update_columns(heartbeat_at: Time.current)
    end

    GoogleSheetsImporter.fetch_rows_in_chunks(sheet_id, chunk_size: BATCH_SIZE) do |chunk, chunk_index|
      chunk_results = process_single_chunk(chunk, chunk_index)

      added   += chunk_results[:added]
      updated += chunk_results[:updated]
      skipped += chunk_results[:skipped]
      failed  += chunk_results[:failed]

      # ── 💓 HEARTBEAT — CADA chunk ──────────────────────────────────────
      if @sync_log&.persisted?
        @sync_log.update_columns(
          heartbeat_at:    Time.current,
          records_synced:  added + updated,
          records_failed:  failed
        )
      end

      # ── 🧹 LIBERACIÓN AGRESIVA DE MEMORIA ─────────────────────────────────
      @auction_cache.clear
      ActiveRecord::Base.connection.clear_query_cache
      GC.start

      # ── 🛡️ MEMORY SAFETY VALVE ─────────────────────────────────────────
      rss = current_rss_mb
      Rails.logger.info "[SyncSheetJob] Chunk #{chunk_index + 1} done | " \
                        "RSS: #{rss} MB | Synced: #{added + updated} | Failed: #{failed}"

      if rss > MAX_RSS_MB
        Rails.logger.error "[SyncSheetJob] 🚨 RSS #{rss} MB > #{MAX_RSS_MB} MB limit! " \
                           "Aborting sync gracefully to prevent OOM SIGKILL."
        raise MemoryLimitExceeded, "RSS #{rss} MB exceeded #{MAX_RSS_MB} MB safety limit " \
                                   "after #{added + updated} rows synced. " \
                                   "Partial sync is safe (idempotent). Re-run to continue."
      end
    end

    { added: added, updated: updated, skipped: skipped, failed: failed }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 🏛️ PIPELINE 2: Condados — Streaming de pestaña "Condados"
  #
  # 🔗 HYPERLINKS: Pre-extrae las URLs embebidas en celdas del Sheet usando
  #   la API avanzada (spreadsheets.get con fields mask). Luego pasa los
  #   hyperlinks de cada fila al CountyRowProcessor para resolver URLs reales.
  # ═══════════════════════════════════════════════════════════════════════════
  def stream_and_process_counties(sheet_id)
    processor = CountyRowProcessor.new

    # ── Pre-fetch hyperlinks (una sola llamada a la API) ──────────────────
    hyperlinks_map = begin
      GoogleSheetsImporter.fetch_county_hyperlinks(sheet_id)
    rescue => e
      Rails.logger.warn "[SyncSheetJob] ⚠️ No se pudieron extraer hyperlinks: #{e.message}. Continuando sin ellos."
      {}
    end

    row_counter = 0

    GoogleSheetsImporter.fetch_counties_in_chunks(sheet_id, chunk_size: BATCH_SIZE) do |chunk, chunk_index|
      chunk.each_with_index do |row, i|
        # El hyperlinks_map usa row_index relativo a fila 2 del Sheet (0-indexed)
        row_idx = (chunk_index * BATCH_SIZE) + i
        row_hyperlinks = hyperlinks_map[row_idx]
        processor.process(row, row_hyperlinks: row_hyperlinks)
        row_counter += 1
      rescue StandardError => e
        processor.stats[:errors] += 1
        row_num = (chunk_index * BATCH_SIZE) + i + 2
        Rails.logger.warn "[SyncSheetJob] Condados fila #{row_num} falló: #{e.message}"
      end

      s = processor.stats
      Rails.logger.info "[SyncSheetJob] 🏛️ Condados chunk #{chunk_index + 1}: " \
                        "+#{s[:created]} created, ~#{s[:updated]} updated, #{s[:skipped]} skipped, #{s[:errors]} errors"

      ActiveRecord::Base.connection.clear_query_cache
      GC.start
    end

    s = processor.stats
    Rails.logger.info "[SyncSheetJob] 🏛️ Condados completado: #{s[:created]} created, #{s[:updated]} updated, " \
                      "#{hyperlinks_map.values.sum { |h| h.size }} hyperlinks resolved"
    { added: s[:created], updated: s[:updated], skipped: s[:skipped], failed: s[:errors] }
  rescue GoogleSheetsImporter::SheetSchemaError => e
    Rails.logger.warn "[SyncSheetJob] ⚠️ Pestaña 'Condados' no disponible o esquema inválido: #{e.message}"
    { added: 0, updated: 0, skipped: 0, failed: 0 }
  rescue Google::Apis::ClientError => e
    Rails.logger.warn "[SyncSheetJob] ⚠️ Pestaña 'Condados' no accesible: #{e.message}"
    { added: 0, updated: 0, skipped: 0, failed: 0 }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 📊 PIPELINE 3: Mercados — Streaming de pestaña "Mercados"
  # ═══════════════════════════════════════════════════════════════════════════
  def stream_and_process_markets(sheet_id)
    processor = nil  # Se inicializa con date_headers del primer yield

    GoogleSheetsImporter.fetch_markets_in_chunks(sheet_id, chunk_size: BATCH_SIZE) do |chunk, chunk_index, date_headers|
      # Inicializar processor con las fechas parseadas (una sola vez)
      processor ||= MarketVolumeRowProcessor.new(date_headers)

      chunk.each_with_index do |row, i|
        processor.process(row)
      rescue StandardError => e
        processor.stats[:errors] += 1
        row_num = (chunk_index * BATCH_SIZE) + i + 4  # Datos empiezan en fila 4
        Rails.logger.warn "[SyncSheetJob] Mercados fila #{row_num} falló: #{e.message}"
      end

      s = processor.stats
      Rails.logger.info "[SyncSheetJob] 📊 Mercados chunk #{chunk_index + 1}: " \
                        "+#{s[:created]} created, ~#{s[:updated]} updated, #{s[:skipped]} skipped, #{s[:errors]} errors"

      ActiveRecord::Base.connection.clear_query_cache
      GC.start
    end

    s = processor&.stats || { created: 0, updated: 0, skipped: 0, errors: 0 }
    Rails.logger.info "[SyncSheetJob] 📊 Mercados completado: #{s[:created]} created, #{s[:updated]} updated"
    { added: s[:created], updated: s[:updated], skipped: s[:skipped], failed: s[:errors] }
  rescue GoogleSheetsImporter::SheetSchemaError => e
    Rails.logger.warn "[SyncSheetJob] ⚠️ Pestaña 'Mercados' no disponible o esquema inválido: #{e.message}"
    { added: 0, updated: 0, skipped: 0, failed: 0 }
  rescue Google::Apis::ClientError => e
    Rails.logger.warn "[SyncSheetJob] ⚠️ Pestaña 'Mercados' no accesible: #{e.message}"
    { added: 0, updated: 0, skipped: 0, failed: 0 }
  end

  # ── Procesa un chunk individual de filas de Propiedades ─────────────────
  def process_single_chunk(chunk, chunk_index)
    added = updated = skipped = failed = 0

    chunk.each_with_index do |row, row_in_chunk|
      global_row = (chunk_index * BATCH_SIZE) + row_in_chunk
      # El hyperlinks_map usa row_index relativo a fila 2 del Sheet (0-indexed)
      row_idx = global_row
      row_hyperlinks = @property_hyperlinks[row_idx]
      result = process_row_with_cache(row, row_hyperlinks: row_hyperlinks)

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

  # ── Procesamiento con cache de Auctions ───────────────────────────────
  def process_row_with_cache(row, row_hyperlinks: nil)
    SheetRowProcessor.process(row, auction_cache: @auction_cache, row_hyperlinks: row_hyperlinks)
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

    # Capturar detalles extra de Google API errors
    extra = ""
    if exception.respond_to?(:status_code)
      extra += " | HTTP #{exception.status_code}"
    end
    if exception.respond_to?(:body) && exception.body.present?
      extra += " | Body: #{exception.body.to_s.truncate(500)}"
    end

    @sync_log&.update!(
      status:           "failed",
      error_message:    "[#{prefix}] #{exception.class}: #{exception.message}#{extra}",
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

  # ── 🚀 MEMORY-SAFE: Actualiza parcel_count con un solo UPDATE SQL ─────
  def refresh_auction_counts
    sql = <<~SQL
      UPDATE auctions
      SET parcel_count = (
        SELECT COUNT(*)
        FROM parcels
        WHERE parcels.auction_id = auctions.id
      )
    SQL
    ActiveRecord::Base.connection.execute(sql)
    Rails.cache.clear
    Rails.logger.info "[SyncSheetJob] ✅ parcel_count actualizado (SQL batch)"
  rescue StandardError => e
    Rails.logger.error "[SyncSheetJob] Error al actualizar parcel_count: #{e.message}"
  end

  # 🧹 GARBAGE COLLECTOR — Purga Auctions huérfanas (0 parcels)
  def cleanup_empty_auctions
    sql = <<~SQL
      DELETE FROM auctions
      WHERE id IN (
        SELECT auctions.id
        FROM auctions
        LEFT JOIN parcels ON parcels.auction_id = auctions.id
        GROUP BY auctions.id
        HAVING COUNT(parcels.id) = 0
      )
    SQL
    result = ActiveRecord::Base.connection.execute(sql)
    count = result.respond_to?(:cmd_tuples) ? result.cmd_tuples : 0
    Rails.logger.info "[SyncSheetJob] 🧹 Cleaned #{count} empty auction records (SQL direct)" if count > 0
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

  # ── 📈 MEMORY MONITOR ──────────────────────────────────────────────────
  def current_rss_mb
    status_file = "/proc/self/status"
    return 0 unless File.exist?(status_file)

    File.readlines(status_file).each do |line|
      if line.start_with?("VmRSS:")
        return (line.split[1].to_i / 1024.0).round(1)
      end
    end
    0
  rescue StandardError
    0
  end
end
