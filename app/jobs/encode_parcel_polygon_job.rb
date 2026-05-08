# frozen_string_literal: true

# EncodeParcelPolygonJob — Pre-computa polygon_encoded para una parcela
#
# Disparado por:
#   - SheetRowProcessor (después del upsert, solo si el parcel es Clear-to-Bid eligible)
#   - Backfill manual: EncodeParcelPolygonJob.perform_later(parcel.id)
#
# Diseño:
#   - Queue :low — no compite con sync ni reports
#   - Idempotente: si ya tiene polygon_encoded reciente, skip
#   - Skip silencioso si el condado no está en COUNTY_GIS_REGISTRY (no es bug)
#   - Skip silencioso si no hay lat/lng (geocoding pendiente)
#   - update_column para evitar callbacks (no toca CRM Immunity)
#
class EncodeParcelPolygonJob < ApplicationJob
  queue_as :low

  # Ratelimit defensive: si ArcGIS de un condado responde 429/timeout,
  # reintentar con backoff polinómico — máx 3 intentos.
  retry_on Net::OpenTimeout, wait: :polynomially_longer, attempts: 3
  retry_on Net::ReadTimeout, wait: :polynomially_longer, attempts: 3

  def perform(parcel_id)
    parcel = Parcel.find_by(id: parcel_id)
    return unless parcel

    # Skip si ya tiene polygon_encoded — los límites de un lote no cambian.
    # Para forzar re-fetch: parcel.update_column(:polygon_encoded, nil) primero.
    return if parcel.polygon_encoded.present?

    encoded = ParcelPolygonEncoder.encode_for(parcel)

    if encoded.present?
      # update_column salta validaciones y callbacks — apropiado aquí: campo
      # derivado y no parte del CRM. No dispara CRM Immunity.
      parcel.update_column(:polygon_encoded, encoded)
      Rails.logger.info(
        "[EncodeParcelPolygonJob] parcel_id=#{parcel.id} encoded length=#{encoded.length}"
      )
    else
      # Falló (condado no soportado, sin lat/lng, ArcGIS down, sin features).
      # NO marcamos en BD — un retry futuro puede tener éxito (ej. condado
      # añadido al registry, geocoding completado). Solo log informativo.
      Rails.logger.info(
        "[EncodeParcelPolygonJob] parcel_id=#{parcel.id} no polygon (county not registered or no features)"
      )
    end
  end
end
