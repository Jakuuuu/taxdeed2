# frozen_string_literal: true

# Api::RegridTilesController — Proxy server-side para Regrid Tile Server
#
# Propósito:
#   Ocultar el REGRID_API_TOKEN del frontend. El cliente solicita tiles
#   sin token, y este controlador los fetcha de Regrid con el token inyectado
#   server-side, retornando la imagen PNG al browser.
#
# Ruta:
#   GET /api/regrid/tiles/:z/:x/:y.png
#
# Seguridad:
#   - Requiere autenticación (before_action :authenticate_user!)
#   - Token NUNCA se expone al cliente
#   - Rate limiting implícito: Regrid limita por token, no por IP
#   - Cache: 1 hora en browser + CDN para reducir requests a Regrid
#
module Api
  class RegridTilesController < ApplicationController
    before_action :authenticate_user!

    # GET /api/regrid/tiles/:z/:x/:y
    def show
      token = ENV["REGRID_API_TOKEN"]
      unless token.present?
        head :service_unavailable
        return
      end

      z = params[:z].to_i
      x = params[:x].to_i
      y = params[:y].to_i

      # Validar rangos de zoom (Regrid soporta 10-21)
      unless z.between?(10, 21)
        head :bad_request
        return
      end

      tile_url = "https://tiles.regrid.com/api/v1/parcels/#{z}/#{x}/#{y}.png?token=#{token}"

      begin
        uri = URI.parse(tile_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "TaxSaleResources/1.0"

        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          # Cache 1 hora en browser, 24h en CDN
          expires_in 1.hour, public: true

          send_data response.body,
                    type: "image/png",
                    disposition: "inline"
        else
          Rails.logger.warn "[RegridTiles] Tile fetch failed: #{response.code} for z=#{z} x=#{x} y=#{y}"
          head :bad_gateway
        end
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        Rails.logger.warn "[RegridTiles] Timeout: #{e.message}"
        head :gateway_timeout
      rescue StandardError => e
        Rails.logger.error "[RegridTiles] Error: #{e.class}: #{e.message}"
        head :internal_server_error
      end
    end
  end
end
