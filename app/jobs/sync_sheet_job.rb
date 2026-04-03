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
#
class SyncSheetJob < ApplicationJob
  queue_as :data_sync

  retry_on Google::Apis::ServerError, wait: :polynomially_longer, attempts: 3
  retry_on Google::Apis::TransmissionError, wait: :polynomially_longer, attempts: 3

  def perform(sheet_id = nil)
    sheet_id ||= ENV.fetch("GOOGLE_SHEETS_SHEET_ID") {
      Rails.application.credentials.dig(:google_sheets, :sheet_id)
    }

    raise ArgumentError, "sheet_id is required" if sheet_id.blank?

    Rails.logger.info "[SyncSheetJob] Iniciando sync de Sheet: #{sheet_id}"
    started_at = Time.current

    rows = GoogleSheetsImporter.fetch_rows(sheet_id)
    Rails.logger.info "[SyncSheetJob] #{rows.size} filas obtenidas del Sheet"

    results = process_rows(rows)

    # Actualizar parcel_count en todas las auctions afectadas
    refresh_auction_counts

    elapsed = (Time.current - started_at).round(1)
    Rails.logger.info "[SyncSheetJob] Completado en #{elapsed}s. " \
                      "Procesadas: #{results[:ok]} | Ignoradas: #{results[:skipped]} | Fallidas: #{results[:failed]}"
  end

  private

  def process_rows(rows)
    ok = 0
    skipped = 0
    failed = 0

    rows.each_with_index do |row, i|
      SheetRowProcessor.process(row)
      ok += 1
    rescue ActiveRecord::RecordInvalid => e
      failed += 1
      Rails.logger.warn "[SyncSheetJob] Fila #{i + 2} inválida: #{e.message}"
    rescue => e
      failed += 1
      Rails.logger.error "[SyncSheetJob] Fila #{i + 2} falló inesperadamente: #{e.class}: #{e.message}"
    end

    { ok: ok, skipped: skipped, failed: failed }
  end

  def refresh_auction_counts
    Auction.find_each do |auction|
      auction.update_column(:parcel_count, auction.parcels.count)
    end
  rescue => e
    Rails.logger.error "[SyncSheetJob] Error al actualizar parcel_count: #{e.message}"
  end
end
