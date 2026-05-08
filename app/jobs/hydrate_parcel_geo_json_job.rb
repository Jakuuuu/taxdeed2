# frozen_string_literal: true

# HydrateParcelGeoJsonJob — Persiste el GeoJSON del polígono de una parcela en la BD
#
# Propósito (Rama 2 — Organic Hydration):
#   Se dispara cuando un usuario abre la ficha de una parcela que no tiene
#   polygon_geojson almacenado. Extrae el polígono del ArcGIS REST del condado
#   (o del FDOR estatal como fallback) y lo guarda en parcels.polygon_geojson.
#
#   La próxima vez que Rama 2 cargue map_data.json, la parcela ya tendrá su
#   polígono disponible → visualización instantánea sin queries externas.
#
# Disparado por:
#   - Research::ParcelsController#show (after_action background)
#   - Backfill manual: HydrateParcelGeoJsonJob.perform_later(parcel.id)
#
# Cobertura:
#   - Todos los condados FL (67) vía FDOR statewide fallback
#   - Condados individuales en COUNTY_GIS_REGISTRY (Palm Beach, Brevard, etc.)
#   - Fuera de FL: solo si el condado tiene entry en COUNTY_GIS_REGISTRY
#
# Diseño:
#   - Queue :low — no compite con sync ni reports
#   - Idempotente: skip si ya tiene polygon_geojson (los límites no cambian)
#   - update_column: evita callbacks y CRM Immunity (campo derivado)
#   - Sin raise en errores — el fallback gracioso es: la parcela muestra marker pin
#
class HydrateParcelGeoJsonJob < ApplicationJob
  queue_as :low

  # Ratelimit defensive: backoff polinómico si ArcGIS responde 429 o timeout
  retry_on Net::OpenTimeout, wait: :polynomially_longer, attempts: 3
  retry_on Net::ReadTimeout, wait: :polynomially_longer, attempts: 3

  def perform(parcel_id)
    parcel = Parcel.find_by(id: parcel_id)
    return unless parcel

    # Skip idempotente — si ya tiene GeoJSON almacenado, no re-fetch.
    # Los límites catastrales de un lote no cambian (salvo rezonificación).
    # Para forzar re-hydration: parcel.update_columns(polygon_geojson: nil, polygon_fetched_at: nil)
    return if parcel.polygon_geojson.present?

    # Requiere coordenadas para la spatial query
    unless parcel.latitude.present? && parcel.longitude.present?
      Rails.logger.info(
        "[HydrateParcelGeoJsonJob] parcel_id=#{parcel.id} skipped — no lat/lng"
      )
      return
    end

    geojson_hash = fetch_geojson(parcel)

    if geojson_hash.nil?
      Rails.logger.info(
        "[HydrateParcelGeoJsonJob] parcel_id=#{parcel.id} no polygon returned " \
        "(county not supported or ArcGIS unavailable)"
      )
      return
    end

    features = geojson_hash["features"] || []
    if features.empty?
      Rails.logger.info(
        "[HydrateParcelGeoJsonJob] parcel_id=#{parcel.id} empty features — skipping persist"
      )
      return
    end

    # Persist — update_column bypasses validations, callbacks y CRM Immunity.
    # polygon_geojson almacena el JSON string completo de la FeatureCollection.
    parcel.update_columns(
      polygon_geojson:    geojson_hash.to_json,
      polygon_fetched_at: Time.current
    )

    Rails.logger.info(
      "[HydrateParcelGeoJsonJob] parcel_id=#{parcel.id} hydrated " \
      "— #{features.size} feature(s), #{parcel.polygon_geojson.bytesize} bytes"
    )
  end

  private

  # Delega la query al LocalGisController internamente (reutiliza la lógica
  # Two-Pass + registry + FDOR fallback sin duplicar código).
  def fetch_geojson(parcel)
    state_up   = parcel.state.to_s.upcase.strip
    state_abbr = Api::LocalGisController::STATE_ABBREVIATIONS[state_up] || state_up
    registry_key = "#{parcel.county.to_s.upcase.strip}|#{state_abbr}"

    config = Api::LocalGisController::COUNTY_GIS_REGISTRY[registry_key]

    # Florida statewide fallback para condados no registrados individualmente
    if config.nil? && state_abbr == "FL"
      Rails.logger.info(
        "[HydrateParcelGeoJsonJob] #{registry_key} not in registry — using FL statewide (FDOR)"
      )
      config = Api::LocalGisController::FLORIDA_STATEWIDE_GIS
    end

    return nil unless config

    lat = parcel.latitude.to_f
    lng = parcel.longitude.to_f

    # Pass 1: punto exacto
    features = arcgis_query(config, lat, lng, :point)

    # Pass 2: envelope con buffer si el punto cayó fuera del polígono
    if features.empty?
      Rails.logger.info(
        "[HydrateParcelGeoJsonJob] parcel_id=#{parcel.id} point miss — trying envelope"
      )
      features = arcgis_query(config, lat, lng, :envelope)
    end

    return nil if features.empty?

    { "type" => "FeatureCollection", "features" => features }
  end

  ENVELOPE_BUFFER = 0.0003  # ±33m, alineado con Api::LocalGisController

  def arcgis_query(config, lat, lng, mode)
    query_params = {
      inSR:              "4326",
      outSR:             "4326",
      spatialRel:        "esriSpatialRelIntersects",
      returnGeometry:    "true",
      outFields:         config[:out_fields],
      resultRecordCount: "1",
      f:                 "geojson"
    }

    if mode == :envelope
      xmin = lng - ENVELOPE_BUFFER
      ymin = lat - ENVELOPE_BUFFER
      xmax = lng + ENVELOPE_BUFFER
      ymax = lat + ENVELOPE_BUFFER
      query_params[:geometry]     = "#{xmin},#{ymin},#{xmax},#{ymax}"
      query_params[:geometryType] = "esriGeometryEnvelope"
    else
      query_params[:geometry]     = "#{lng},#{lat}"
      query_params[:geometryType] = "esriGeometryPoint"
    end

    uri  = URI.parse("#{config[:url]}?#{query_params.to_query}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.open_timeout = 8
    http.read_timeout = 15

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "TaxSaleResources/HydrateJob"
    request["Accept"]     = "application/json"

    response = http.request(request)
    return [] unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).fetch("features", [])
  rescue Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError, StandardError => e
    Rails.logger.warn(
      "[HydrateParcelGeoJsonJob] arcgis_query #{mode} failed: #{e.class}: #{e.message}"
    )
    []
  end
end
