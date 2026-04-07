# frozen_string_literal: true

# RegridClient — HTTP client for the Regrid Parcel API
#
# Responsabilidades:
#   - Geocodificar parcelas por dirección (address → lat/lng)
#   - Extraer coordenadas de la respuesta GeoJSON
#   - Health check de la API key
#
# Seguridad:
#   ❌ NUNCA loguear el token
#   ❌ NUNCA incluir el token en mensajes de error
#   ✅ Token vive SOLO en ENV['REGRID_API_TOKEN']
#
# Uso:
#   client = RegridClient.new
#   result = client.geocode(address: "123 Main St", state: "FL", county: "Escambia")
#   # => { latitude: 30.4213, longitude: -87.2169 }  o  nil
#
require "net/http"
require "json"
require "uri"

class RegridClient
  BASE_URL = "https://app.regrid.com/api/v2/parcels/address"

  # Timeout generoso para API externa
  READ_TIMEOUT  = 15
  OPEN_TIMEOUT  = 10

  class ConfigurationError < StandardError; end
  class AuthenticationError < StandardError; end
  class RateLimitError < StandardError; end

  def initialize
    @token = ENV["REGRID_API_TOKEN"]
    if @token.blank?
      raise ConfigurationError, "REGRID_API_TOKEN is not set in environment"
    end
  end

  # Geocodifica una dirección y retorna { latitude:, longitude: } o nil
  #
  # @param address [String] la dirección a buscar (ej: "123 Main St")
  # @param state   [String] código de estado de 2 letras (ej: "FL")
  # @param county  [String] nombre del condado (ej: "Escambia")
  # @return [Hash, nil] { latitude: BigDecimal, longitude: BigDecimal } o nil
  def geocode(address:, state: nil, county: nil)
    return nil if address.blank?

    params = build_params(address, state, county)
    response = execute_request(params)

    return nil unless response

    extract_coordinates(response)
  end

  # Verifica que la API key sea válida haciendo un request mínimo
  #
  # @return [Boolean] true si la key es válida
  def test_connection
    params = build_params("1600 Pennsylvania Ave", "DC", nil)
    uri = build_uri(params)
    response = perform_http_get(uri)
    response.is_a?(Net::HTTPSuccess)
  rescue StandardError => e
    Rails.logger.error "[RegridClient] Health check failed: #{e.class}: #{e.message}"
    false
  end

  private

  # ── Construcción de la Request ─────────────────────────────────────────────

  def build_params(address, state, county)
    params = {
      "token" => @token,
      "query" => address,
      "limit" => "1"
    }

    # Narrow búsqueda por state/county para mayor precisión
    path = build_path(state, county)
    params["path"] = path if path.present?

    params
  end

  def build_path(state, county)
    return nil if state.blank?

    parts = ["/us", state.downcase.strip]

    if county.present?
      # Normalizar county: "Escambia County" → "escambia"
      # Regrid usa slugs sin "County" suffix
      county_slug = county.downcase
                         .gsub(/\s*county\s*/i, "")
                         .strip
                         .gsub(/\s+/, "-")
      parts << county_slug
    end

    parts.join("/")
  end

  def build_uri(params)
    uri = URI.parse(BASE_URL)
    uri.query = URI.encode_www_form(params)
    uri
  end

  # ── HTTP Execution ─────────────────────────────────────────────────────────

  def execute_request(params)
    uri = build_uri(params)

    # Log sanitizado (sin token)
    sanitized = params.except("token")
    Rails.logger.debug "[RegridClient] Query: #{sanitized.inspect}"

    response = perform_http_get(uri)

    case response
    when Net::HTTPSuccess
      JSON.parse(response.body)
    when Net::HTTPUnauthorized
      raise AuthenticationError, "Regrid API returned 401 — API key may be invalid or expired"
    when Net::HTTPTooManyRequests
      raise RateLimitError, "Regrid API returned 429 — rate limit exceeded"
    else
      Rails.logger.warn "[RegridClient] Unexpected response: #{response.code} #{response.message}"
      nil
    end
  end

  def perform_http_get(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = READ_TIMEOUT
    http.open_timeout = OPEN_TIMEOUT

    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"
    request["User-Agent"] = "TaxSaleResources/1.0"

    http.request(request)
  end

  # ── Extracción de Coordenadas ──────────────────────────────────────────────

  def extract_coordinates(geojson)
    features = geojson.dig("features")
    return nil if features.blank? || features.empty?

    feature = features.first
    return nil if feature.blank?

    # Prioridad 1: properties.lat / properties.lon
    props = feature["properties"] || {}
    lat = props["lat"]
    lon = props["lon"]

    if lat.present? && lon.present?
      return {
        latitude:  BigDecimal(lat.to_s),
        longitude: BigDecimal(lon.to_s)
      }
    end

    # Prioridad 2: Calcular centroide del geometry
    geometry = feature["geometry"]
    return nil if geometry.blank?

    centroid = calculate_centroid(geometry)
    return nil if centroid.nil?

    {
      latitude:  BigDecimal(centroid[:lat].to_s),
      longitude: BigDecimal(centroid[:lon].to_s)
    }
  end

  # Calcula el centroide aproximado de un GeoJSON geometry
  # Soporta Polygon y MultiPolygon
  def calculate_centroid(geometry)
    coordinates = geometry["coordinates"]
    return nil if coordinates.blank?

    type = geometry["type"]

    points = case type
             when "Polygon"
               # coordinates = [[[lng, lat], ...]]
               coordinates.first || []
             when "MultiPolygon"
               # coordinates = [[[[lng, lat], ...]], ...]
               coordinates.flat_map { |polygon| polygon.first || [] }
             when "Point"
               # coordinates = [lng, lat]
               [coordinates]
             else
               Rails.logger.warn "[RegridClient] Unsupported geometry type: #{type}"
               return nil
             end

    return nil if points.empty?

    # Promedio simple de coordenadas (centroide aproximado)
    sum_lon = points.sum { |p| p[0].to_f }
    sum_lat = points.sum { |p| p[1].to_f }
    count   = points.size.to_f

    {
      lat: (sum_lat / count).round(8),
      lon: (sum_lon / count).round(8)
    }
  end
end
