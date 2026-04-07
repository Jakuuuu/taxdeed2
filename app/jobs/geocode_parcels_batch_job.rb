# frozen_string_literal: true

# GeocodeParcelsBatchJob — Geocodifica parcelas sin coordenadas usando Regrid API
#
# Disparado por:
#   SyncSheetJob (después de importar filas del Sheet)
#
# Diseño:
#   - Queue :low para no competir con sync ni reports
#   - Rate limiting: sleep(0.3) entre requests (~200 req/min máximo de Regrid)
#   - Error por parcel individual NO para el batch
#   - Usa update_columns para evitar callbacks y validaciones innecesarias
#   - Auth error (401) para todo el job — no tiene sentido seguir con key inválida
#
class GeocodeParcelsBatchJob < ApplicationJob
  queue_as :low

  # Si Regrid tiene rate limit, reintentar con backoff
  retry_on RegridClient::RateLimitError, wait: :polynomially_longer, attempts: 3

  # Si la key es inválida, NO reintentar — requiere intervención manual
  discard_on RegridClient::ConfigurationError
  discard_on RegridClient::AuthenticationError

  def perform(parcel_ids)
    return if parcel_ids.blank?

    begin
      client = RegridClient.new
    rescue RegridClient::ConfigurationError => e
      Rails.logger.error "[GeocodeJob] #{e.message} — skipping geocoding entirely"
      return
    end

    parcels = Parcel.where(id: parcel_ids, latitude: nil)
    total   = parcels.count
    success = 0
    failed  = 0

    Rails.logger.info "[GeocodeJob] Starting geocoding for #{total} parcels"

    parcels.find_each do |parcel|
      geocode_single_parcel(client, parcel)
      success += 1
      sleep(0.3) # Rate limiting: ~200 req/min
    rescue RegridClient::AuthenticationError => e
      Rails.logger.error "[GeocodeJob] Auth error — stopping batch: #{e.message}"
      raise # Re-raise to stop the entire job
    rescue RegridClient::RateLimitError
      raise # Re-raise so Sidekiq can retry with backoff
    rescue => e
      failed += 1
      Rails.logger.warn "[GeocodeJob] Parcel ##{parcel.id} (#{parcel.parcel_id}) failed: #{e.class}: #{e.message}"
    end

    Rails.logger.info "[GeocodeJob] Completed. Success: #{success}/#{total}, Failed: #{failed}"
  end

  private

  def geocode_single_parcel(client, parcel)
    # Usar property_address (dirección física) con fallback a address (dirección de remate)
    address = parcel.property_address.presence || parcel.address
    return if address.blank?

    result = client.geocode(
      address: address,
      state:   parcel.state,
      county:  parcel.county
    )

    if result
      parcel.update_columns(
        latitude:   result[:latitude],
        longitude:  result[:longitude],
        updated_at: Time.current
      )
      Rails.logger.debug "[GeocodeJob] ✅ Parcel ##{parcel.id} → #{result[:latitude]}, #{result[:longitude]}"
    else
      Rails.logger.debug "[GeocodeJob] ⏭️ Parcel ##{parcel.id} — no coordinates found via Regrid"
    end
  end
end
