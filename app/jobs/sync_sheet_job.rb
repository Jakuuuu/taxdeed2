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
class SyncSheetJob < ApplicationJob
  queue_as :data_sync

  BATCH_SIZE = 100

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

      # ── 3. Extracción e importación ──────────────────────────────────────────
      data    = GoogleSheetsImporter.fetch_headers_and_rows(sheet_id)
      headers = data[:headers]
      rows    = data[:rows]

      Rails.logger.info "[SyncSheetJob] 🛡️ Headers validados OK (#{headers.size} columnas, #{rows.size} filas)"

      results = process_rows_in_batches(rows)
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
  rescue => e
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

  def process_rows_in_batches(rows)
    added = updated = skipped = failed = 0
    total_rows = rows.size
    total_batches = (total_rows.to_f / BATCH_SIZE).ceil

    Rails.logger.info "[SyncSheetJob] Procesando #{total_rows} filas en #{total_batches} lotes de #{BATCH_SIZE}"

    rows.each_slice(BATCH_SIZE).with_index do |batch, batch_idx|
      batch.each_with_index do |row, row_in_batch|
        global_row = (batch_idx * BATCH_SIZE) + row_in_batch
        result = SheetRowProcessor.process(row)

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

      processed_so_far = [((batch_idx + 1) * BATCH_SIZE), total_rows].min
      Rails.logger.info "[SyncSheetJob] Lote #{batch_idx + 1}/#{total_batches} completado (#{processed_so_far}/#{total_rows} filas)"
      GC.start if batch_idx < total_batches - 1
    end

    { added: added, updated: updated, skipped: skipped, failed: failed }
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
