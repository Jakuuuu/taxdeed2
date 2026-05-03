# frozen_string_literal: true

# Api::RegridTilesController — Proxy server-side para Regrid Tile Server y GeoJSON
#
# Propósito:
#   Ocultar el REGRID_API_TOKEN del frontend. El cliente solicita tiles y GeoJSON
#   sin token, y este controlador los fetcha de Regrid con el token inyectado
#   server-side, retornando el recurso al browser.
#
# Rutas:
#   GET /api/regrid/tiles/:z/:x/:y  → #show   (tiles PNG para el mapa)
#   GET /api/regrid/geojson         → #geojson (boundaries GeoJSON de una parcela)
#
# Seguridad:
#   - Requiere autenticación (before_action :authenticate_user!)
#   - Token NUNCA se expone al cliente (lee ENV["REGRID_API_TOKEN"] || ENV["REGRID_API_KEY"])
#   - Rate limiting implícito: Regrid limita por token, no por IP
#   - Cache: 1 hora en browser + CDN para reducir requests a Regrid (tiles solamente)
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

    # GET /api/regrid/geojson?lat=...&lng=...
    def geojson
      # El frontend usaba REGRID_API_KEY, pero el backend usaba REGRID_API_TOKEN
      # Comprobamos ambos por seguridad
      token = ENV["REGRID_API_TOKEN"] || ENV["REGRID_API_KEY"]
      unless token.present?
        head :service_unavailable
        return
      end

      lat = params[:lat]
      lng = params[:lng]

      unless lat.present? && lng.present?
        head :bad_request
        return
      end

      # Regrid API v1 — search.json returns parcels as GeoJSON Features
      # Docs: GET /api/v1/search.json?lat=<y>&lon=<x>&token=<token>
      geojson_url = "https://app.regrid.com/api/v1/search.json?lat=#{lat}&lon=#{lng}&token=#{token}&return_geometry=true"

      begin
        uri = URI.parse(geojson_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "TaxSaleResources/1.0"
        request["Accept"] = "application/json"

        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          # Regrid wraps results in { "results": [Feature, ...] }
          # Normalize to a standard GeoJSON FeatureCollection for the frontend
          raw = JSON.parse(response.body)
          features = raw["results"] || []

          feature_collection = {
            type: "FeatureCollection",
            features: features
          }

          Rails.logger.info "[RegridGeojson] OK — #{features.size} feature(s) for lat=#{lat} lng=#{lng}"

          expires_in 1.day, public: false
          render json: feature_collection, status: :ok
        else
          Rails.logger.warn "[RegridGeojson] Fetch failed: #{response.code} for lat=#{lat} lng=#{lng}"
          Rails.logger.warn "[RegridGeojson] Response body: #{response.body.to_s.truncate(500)}"
          head :bad_gateway
        end
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        Rails.logger.warn "[RegridGeojson] Timeout: #{e.message}"
        head :gateway_timeout
      rescue StandardError => e
        Rails.logger.error "[RegridGeojson] Error: #{e.class}: #{e.message}"
        head :internal_server_error
      end
    end
  end
end
