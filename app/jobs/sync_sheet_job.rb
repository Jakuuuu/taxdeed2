# frozen_string_literal: true

# SyncSheetJob — Importa propiedades desde Google Sheets a PostgreSQL
#
# Disparado por:
#   1. Sidekiq-cron: cada 12h (3:00 AM + 3:00 PM ET = "0 7,19 * * *" UTC)
#   2. Admin manual: POST /admin/sync/run_now
#
# Diseño:
#   - Fila que falla → se loguea y continúa (no para el batch)
#   - 🛡️ SheetSchemaError → job ABORTA completo (headers maestros ausentes)
#   - Error de red Google API → job falla → Sidekiq retry automático (max 3)
#   - Idempotente: upsert por (state+county+parcel_id)
#   - Registra resultado en SyncLog para el Sync Dashboard del admin
#   - Post-sync: encola geocodificación para parcelas sin coordenadas
#   - Procesamiento en lotes de BATCH_SIZE filas para controlar memoria
#
# ⛔ CRM IMMUNITY: parcel_user_tags y parcel_user_notes JAMÁS se tocan.
# 🧹 SANITIZACIÓN: Todos los campos pasan por el módulo Sanitize.
#
class SyncSheetJob < ApplicationJob
  queue_as :data_sync

  # Lote de procesamiento para controlar memoria (OOM) en Render
  BATCH_SIZE = 100

  retry_on Google::Apis::ServerError, wait: :polynomially_longer, attempts: 3
  retry_on Google::Apis::TransmissionError, wait: :polynomially_longer, attempts: 3

  def perform(sheet_id = nil, sync_log_id = nil)
    sheet_id ||= ENV.fetch("GOOGLE_SHEETS_SHEET_ID") {
      Rails.application.credentials.dig(:google_sheets, :sheet_id)
    }

    raise ArgumentError, "sheet_id is required" if sheet_id.blank?

    sync_log = SyncLog.find_by(id: sync_log_id) if sync_log_id.present?
    sync_log ||= SyncLog.create!(status: "running", started_at: Time.current)

    Rails.logger.info "[SyncSheetJob] Iniciando sync de Sheet: #{sheet_id} (log_id: #{sync_log.id})"
    started_at = Time.current

    # 🛡️ fetch_headers_and_rows incluye validate_headers!
    # Si headers maestros faltan → SheetSchemaError → rescue abajo
    data    = GoogleSheetsImporter.fetch_headers_and_rows(sheet_id)
    headers = data[:headers]
    rows    = data[:rows]

    Rails.logger.info "[SyncSheetJob] 🛡️ Headers validados OK (#{headers.size} columnas, #{rows.size} filas)"

    results = process_rows_in_batches(rows)
    refresh_auction_counts

    # ── POST-SYNC: Geocodificación automática ──────────────────────────────
    enqueue_geocoding(started_at)

    elapsed = (Time.current - started_at).round(1)
    Rails.logger.info "[SyncSheetJob] Completado en #{elapsed}s. " \
                      "Added: #{results[:added]} | Updated: #{results[:updated]} | " \
                      "Skipped: #{results[:skipped]} | Failed: #{results[:failed]}"

    sync_log.update!(
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
    # 🛡️ Header failsafe — abort total, ya logueado en SyncLog por validate_headers!
    elapsed = (Time.current - (started_at || Time.current)).round(1)
    sync_log&.update!(
      status:           "failed",
      error_message:    e.message,
      duration_seconds: elapsed,
      completed_at:     Time.current,
      records_synced:   0,
      records_failed:   0
    )
    raise # Re-raise para que Sidekiq registre el fallo

  rescue => e
    elapsed = (Time.current - (started_at || Time.current)).round(1)
    sync_log&.update!(
      status:           "failed",
      error_message:    "#{e.class}: #{e.message}",
      duration_seconds: elapsed,
      completed_at:     Time.current
    )
    raise
  end

  private

  # ── Procesamiento en lotes ─────────────────────────────────────────────────
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
      rescue => e
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
  rescue => e
    Rails.logger.error "[SyncSheetJob] Error al actualizar parcel_count: #{e.message}"
  end

  # ── Geocodificación post-sync (FALLBACK) ──────────────────────────────────
  def enqueue_geocoding(sync_started_at)
    return unless ENV["REGRID_API_TOKEN"].present?

    synced = Parcel.where("last_synced_at >= ?", sync_started_at)
    total  = synced.count
    with_coords    = synced.where.not(latitude: nil).count
    without_coords = synced.where(latitude: nil).pluck(:id)

    Rails.logger.info "[SyncSheetJob] 📊 Coords: #{with_coords}/#{total} from Sheet, #{without_coords.size} need Regrid fallback"

    return if without_coords.empty?

    Rails.logger.info "[SyncSheetJob] 🌐 Enqueuing Regrid geocoding for #{without_coords.size} parcels"
    GeocodeParcelsBatchJob.perform_later(without_coords)
  rescue => e
    Rails.logger.warn "[SyncSheetJob] Geocoding enqueue failed (non-fatal): #{e.message}"
  end
end
