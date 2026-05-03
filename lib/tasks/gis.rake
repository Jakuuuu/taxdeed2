# frozen_string_literal: true

# Healthcheck de los endpoints ArcGIS REST registrados en
# Api::LocalGisController::COUNTY_GIS_REGISTRY.
#
# Uso:
#   bin/rake gis:validate_registry
#
# Itera cada condado del registry, ejecuta una query esriGeometryPoint con
# coordenadas centrales del condado, y reporta HTTP status + features.size.
# Sirve para detectar tempranamente: endpoints caidos, campos out_fields
# eliminados, o cambios estructurales del servicio.

namespace :gis do
  # Coordenadas centrales (city seat) por condado registrado.
  # Si agregas un condado a COUNTY_GIS_REGISTRY, agrega tambien sus coords aqui.
  TEST_COORDINATES = {
    "PALM BEACH|FL"   => [26.7153, -80.0534],   # West Palm Beach
    "BREVARD|FL"      => [28.0836, -80.6081],   # Titusville
    "HILLSBOROUGH|FL" => [27.9477, -82.4584],   # Tampa
    "MARION|FL"       => [29.1872, -82.1401],   # Ocala
    "PUTNAM|FL"       => [29.6594, -81.6628],   # Palatka
    "WASHINGTON|FL"   => [30.6121, -85.6608]    # Chipley
  }.freeze

  desc "Validar conectividad y respuesta de cada endpoint ArcGIS del registry"
  task validate_registry: :environment do
    require "net/http"
    require "json"

    registry = Api::LocalGisController::COUNTY_GIS_REGISTRY
    puts "\n=== GIS Registry Healthcheck (#{registry.size} condados) ==="
    puts

    pass_count = 0
    fail_count = 0
    no_features_count = 0

    registry.each do |key, config|
      coords = TEST_COORDINATES[key]
      unless coords
        puts "  [SKIP] #{key}: sin coordenadas de prueba en TEST_COORDINATES"
        fail_count += 1
        next
      end

      lat, lng = coords
      result = query_arcgis(config, lat, lng)

      case result[:status]
      when :ok
        if result[:features].positive?
          puts "  [OK]   #{key.ljust(20)} HTTP #{result[:code]} | #{result[:features]} feature(s)"
          pass_count += 1
        else
          puts "  [WARN] #{key.ljust(20)} HTTP #{result[:code]} | 0 features (revisa coords o capa)"
          no_features_count += 1
        end
      when :http_error
        puts "  [FAIL] #{key.ljust(20)} HTTP #{result[:code]} | #{result[:body_preview]}"
        fail_count += 1
      when :timeout
        puts "  [FAIL] #{key.ljust(20)} TIMEOUT | #{result[:message]}"
        fail_count += 1
      when :parse_error
        puts "  [FAIL] #{key.ljust(20)} INVALID JSON | #{result[:message]}"
        fail_count += 1
      when :error
        puts "  [FAIL] #{key.ljust(20)} #{result[:klass]} | #{result[:message]}"
        fail_count += 1
      end
    end

    puts
    puts "=== Resumen: #{pass_count} OK, #{no_features_count} sin features, #{fail_count} FAIL ==="

    exit 1 if fail_count.positive?
  end

  # Ejecuta una esriGeometryPoint contra el endpoint ArcGIS y devuelve un hash
  # con :status (:ok, :http_error, :timeout, :parse_error, :error) y datos.
  def query_arcgis(config, lat, lng)
    query_params = {
      inSR:              "4326",
      outSR:             "4326",
      spatialRel:        "esriSpatialRelIntersects",
      geometryType:      "esriGeometryPoint",
      geometry:          "#{lng},#{lat}",
      returnGeometry:    "true",
      outFields:         config[:out_fields],
      resultRecordCount: "1",
      f:                 "geojson"
    }

    uri = URI.parse("#{config[:url]}?#{query_params.to_query}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "TaxSaleResources/1.0 (gis:validate_registry)"
    request["Accept"]     = "application/json"

    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      geojson = JSON.parse(response.body)
      { status: :ok, code: response.code, features: (geojson["features"] || []).size }
    else
      { status: :http_error, code: response.code, body_preview: response.body.to_s[0, 80] }
    end
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    { status: :timeout, message: e.message }
  rescue JSON::ParserError => e
    { status: :parse_error, message: e.message }
  rescue StandardError => e
    { status: :error, klass: e.class.to_s, message: e.message }
  end
end
