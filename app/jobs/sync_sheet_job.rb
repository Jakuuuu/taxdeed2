# frozen_string_literal: true

# SyncSheetJob — Importa propiedades desde Google Sheets a PostgreSQL
#
# Disparado por:
#   1. Sidekiq-cron: todos los días a las 3:00 AM ET (7:00 AM UTC)
#   2. Admin manual: POST /admin/sync/run_now
#
# Diseño:
#   - Fila que falla → se loguea y continúa (no para el batch)
#   - Error de red Google API → job falla completo → Sidekiq retry automático (max 3)
#   - Idempotente: upsert por parcel_id, auction por (county+state+sale_date)
#   - Registra resultado en SyncLog para el Sync Dashboard del admin
#   - Post-sync: encola geocodificación para parcelas sin coordenadas (Regrid API)
#
class SyncSheetJob < ApplicationJob
  queue_as :data_sync

  retry_on Google::Apis::ServerError, wait: :polynomially_longer, attempts: 3
  retry_on Google::Apis::TransmissionError, wait: :polynomially_longer, attempts: 3

  def perform(sheet_id = nil, sync_log_id = nil)
    sheet_id ||= ENV.fetch("GOOGLE_SHEETS_SHEET_ID") {
      Rails.application.credentials.dig(:google_sheets, :sheet_id)
    }

    raise ArgumentError, "sheet_id is required" if sheet_id.blank?

    sync_log = SyncLog.find_by(id: sync_log_id) if sync_log_id.present?
    # Si se llamó sin sync_log_id (cron automático), crear uno ahora
    sync_log ||= SyncLog.create!(status: "running", started_at: Time.current)

    Rails.logger.info "[SyncSheetJob] Iniciando sync de Sheet: #{sheet_id} (log_id: #{sync_log.id})"
    started_at = Time.current

    rows    = GoogleSheetsImporter.fetch_rows(sheet_id)
    results = process_rows(rows)
    refresh_auction_counts

    # ── POST-SYNC: Geocodificación automática ──────────────────────────────
    enqueue_geocoding(started_at)

    elapsed = (Time.current - started_at).round(1)
    Rails.logger.info "[SyncSheetJob] Completado en #{elapsed}s. " \
                      "Procesadas: #{results[:ok]} | Ignoradas: #{results[:skipped]} | Fallidas: #{results[:failed]}"

    sync_log.update!(
      status:           "success",
      parcels_added:    results[:added],
      parcels_updated:  results[:updated],
      parcels_skipped:  results[:skipped],
      duration_seconds: elapsed,
      completed_at:     Time.current
    )

  rescue => e
    elapsed = (Time.current - (started_at || Time.current)).round(1)
    sync_log&.update!(
      status:           "failed",
      error_message:    "#{e.class}: #{e.message}",
      duration_seconds: elapsed,
      completed_at:     Time.current
    )
    raise # re-raise so Sidekiq retries / marks as failed
  end

  private

  def process_rows(rows)
    ok = added = updated = skipped = failed = 0

    rows.each_with_index do |row, i|
      SheetRowProcessor.process(row)
      ok += 1
      # SheetRowProcessor should return :added/:updated/:skipped — stubbed as added for now
      added += 1
    rescue ActiveRecord::RecordInvalid => e
      failed += 1
      Rails.logger.warn "[SyncSheetJob] Fila #{i + 2} inválida: #{e.message}"
    rescue => e
      failed += 1
      Rails.logger.error "[SyncSheetJob] Fila #{i + 2} falló inesperadamente: #{e.class}: #{e.message}"
    end

    { ok: ok, added: added, updated: updated, skipped: skipped, failed: failed }
  end

  def refresh_auction_counts
    Auction.find_each do |auction|
      auction.update_column(:parcel_count, auction.parcels.count)
    end
  rescue => e
    Rails.logger.error "[SyncSheetJob] Error al actualizar parcel_count: #{e.message}"
  end

  # ── Geocodificación post-sync (FALLBACK) ──────────────────────────────────
  # Fuente primaria de coordenadas: Google Sheet columna AJ (COORDINATES_RAW)
  # Si la columna AJ está vacía, encola geocodificación vía Regrid API como fallback.
  #
  # Este paso es fire-and-forget: si falla el enqueue, NO afecta el resultado
  # del sync principal. Las parcelas se geocodificarán en el siguiente ciclo.
  def enqueue_geocoding(sync_started_at)
    return unless ENV["REGRID_API_TOKEN"].present?

    synced = Parcel.where("last_synced_at >= ?", sync_started_at)
    total  = synced.count
    with_coords    = synced.where.not(latitude: nil).count
    without_coords = synced.where(latitude: nil).pluck(:id)

    Rails.logger.info "[SyncSheetJob] 📊 Coords: #{with_coords}/#{total} from Sheet, #{without_coords.size} need Regrid fallback"

    return if without_coords.empty?

    Rails.logger.info "[SyncSheetJob] 🌐 Enqueuing Regrid geocoding for #{without_coords.size} parcels missing Sheet coordinates"
    GeocodeParcelsBatchJob.perform_later(without_coords)
  rescue => e
    # No interrumpir el sync por errores de geocodificación
    Rails.logger.warn "[SyncSheetJob] Geocoding enqueue failed (non-fatal): #{e.message}"
  end
end
