# frozen_string_literal: true

# SyncSheetJob — Importa propiedades desde Google Sheets a PostgreSQL
#
# Disparado por:
#   1. Sidekiq-cron: 3x/día cada 8h (3:00 AM, 11:00 AM, 7:00 PM ET)
#   2. Admin manual: POST /admin/sync/run_now
#
# Diseño:
#   - Fila que falla → se loguea y continúa (no para el batch)
#   - Error de red Google API → job falla completo → Sidekiq retry automático (max 3)
#   - Idempotente: upsert por parcel_id, auction por (county+state+sale_date)
#   - Registra resultado en SyncLog para el Sync Dashboard del admin
#   - Post-sync: encola geocodificación para parcelas sin coordenadas (Regrid API)
#   - Procesamiento en lotes de BATCH_SIZE filas para controlar memoria en Render
#
# 🪞 ESPEJO INFALIBLE:
#   Celdas borradas en Sheet → nil en PostgreSQL (obligatorio).
#   El SheetRowProcessor maneja la conversión blank→nil en cada campo.
#
# 🛡️ MAPEO RESILIENTE:
#   Cabeceras del Sheet se normalizan (.strip) para proteger contra
#   caracteres invisibles. Se logea la fila de cabeceras para auditoría.
#
# ⛔ CRM IMMUNITY:
#   parcel_user_tags y parcel_user_notes JAMÁS se tocan.
#   Garantizado por enforce_crm_immunity! en SheetRowProcessor.
#
class SyncSheetJob < ApplicationJob
  queue_as :data_sync

  # ── Lote de procesamiento ────────────────────────────────────────────────────
  # Procesar filas en lotes de 100 para evitar picos de memoria (OOM) en Render.
  # Después de cada lote se sugiere GC y se loguea progreso incremental.
  BATCH_SIZE = 100

  # Cabeceras esperadas en posiciones clave (para validación de integridad)
  EXPECTED_HEADERS = {
    0 => "State",
    1 => "County",
    2 => "Parcel Number",
    6 => "Auction Date",
    8 => "Min. Bid"
  }.freeze

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

    # 🛡️ MAPEO RESILIENTE: Fetch con cabeceras normalizadas para validación
    data    = GoogleSheetsImporter.fetch_headers_and_rows(sheet_id)
    headers = data[:headers]
    rows    = data[:rows]

    validate_headers(headers)

    results = process_rows_in_batches(rows)
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

  # ── Validación de cabeceras ──────────────────────────────────────────────────
  # 🛡️ MAPEO RESILIENTE: Compara las cabeceras normalizadas contra las esperadas.
  # Si alguna cabecera clave no coincide, loguea WARNING (no bloquea el sync,
  # ya que el procesamiento es posicional y una cabecera renombrada no rompe nada,
  # pero alerta al equipo de que el Sheet pudo haber cambiado de estructura).
  def validate_headers(headers)
    Rails.logger.info "[SyncSheetJob] 🛡️ Headers normalizados (primeros 10): #{headers.first(10).inspect}"

    mismatches = []
    EXPECTED_HEADERS.each do |index, expected_name|
      actual = headers[index]&.strip
      # Comparación case-insensitive para tolerar variaciones menores
      unless actual&.downcase == expected_name.downcase
        mismatches << "col[#{index}]: esperado='#{expected_name}', actual='#{actual || '(vacío)'}'"
      end
    end

    if mismatches.any?
      Rails.logger.warn "[SyncSheetJob] ⚠️ HEADER MISMATCH detectado. " \
                        "El Sheet podría haber cambiado de estructura: #{mismatches.join(' | ')}"
    else
      Rails.logger.info "[SyncSheetJob] ✅ Headers validados correctamente"
    end
  end

  # ── Procesamiento en lotes ─────────────────────────────────────────────────
  # Divide las filas del Sheet en lotes de BATCH_SIZE para:
  #   1. Controlar presión de memoria (objetos AR temporales se liberan entre lotes)
  #   2. Dar visibilidad de progreso en los logs
  #   3. Permitir GC entre lotes para evitar OOM en Render Starter plan
  def process_rows_in_batches(rows)
    ok = added = updated = skipped = failed = 0
    total_rows = rows.size
    total_batches = (total_rows.to_f / BATCH_SIZE).ceil

    Rails.logger.info "[SyncSheetJob] Procesando #{total_rows} filas en #{total_batches} lotes de #{BATCH_SIZE}"

    rows.each_slice(BATCH_SIZE).with_index do |batch, batch_idx|
      batch.each_with_index do |row, row_in_batch|
        global_row = (batch_idx * BATCH_SIZE) + row_in_batch
        SheetRowProcessor.process(row)
        ok += 1
        added += 1
      rescue ActiveRecord::RecordInvalid => e
        failed += 1
        Rails.logger.warn "[SyncSheetJob] Fila #{global_row + 2} inválida: #{e.message}"
      rescue ActiveRecord::RecordNotSaved => e
        failed += 1
        Rails.logger.error "[SyncSheetJob] Fila #{global_row + 2} bloqueada (CRM immunity?): #{e.message}"
      rescue => e
        failed += 1
        Rails.logger.error "[SyncSheetJob] Fila #{global_row + 2} falló inesperadamente: #{e.class}: #{e.message}"
      end

      # Logging de progreso y hint de GC entre lotes
      processed_so_far = [((batch_idx + 1) * BATCH_SIZE), total_rows].min
      Rails.logger.info "[SyncSheetJob] Lote #{batch_idx + 1}/#{total_batches} completado (#{processed_so_far}/#{total_rows} filas)"
      GC.start if batch_idx < total_batches - 1 # No GC en el último lote (innecesario)
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
