# frozen_string_literal: true

# RegridKeyHealthCheckJob — Verificación mensual de la API key de Regrid
#
# Disparado por:
#   Sidekiq-cron: día 1 de cada mes a las 12:00 UTC (8:00 AM ET)
#
# La API key de Regrid vence mensualmente. Este job:
#   1. Hace un request de prueba a la API
#   2. Loguea si la key es válida o ha expirado
#   3. (Futuro) Envía email de alerta al admin si ha expirado
#
# Acción requerida si falla:
#   → Admin renueva la key en https://app.regrid.com/profile#api
#   → Admin actualiza REGRID_API_TOKEN en Render Dashboard
#
class RegridKeyHealthCheckJob < ApplicationJob
  queue_as :low

  discard_on RegridClient::ConfigurationError

  def perform
    begin
      client = RegridClient.new
    rescue RegridClient::ConfigurationError => e
      Rails.logger.error "[RegridKeyHealth] ❌ #{e.message}"
      Rails.logger.error "[RegridKeyHealth] → Configure REGRID_API_TOKEN in environment"
      return
    end

    valid = client.test_connection

    if valid
      Rails.logger.info "[RegridKeyHealth] ✅ API key is valid and active"
    else
      Rails.logger.error "[RegridKeyHealth] ❌ API key is INVALID or EXPIRED"
      Rails.logger.error "[RegridKeyHealth] → ACTION REQUIRED: Update REGRID_API_TOKEN"
      Rails.logger.error "[RegridKeyHealth] → 1. Login to https://app.regrid.com/profile#api"
      Rails.logger.error "[RegridKeyHealth] → 2. Generate a new API token"
      Rails.logger.error "[RegridKeyHealth] → 3. Update REGRID_API_TOKEN in Render Dashboard"
      # TODO: AdminMailer.regrid_key_expired.deliver_later
    end
  end
end
