# frozen_string_literal: true

# ParcelPolygonEncoder — Pre-computa la encoded polyline del polígono de una parcela
#
# Pipeline:
#   parcel (lat/lng + county + state)
#     → COUNTY_GIS_REGISTRY lookup
#     → ArcGIS REST spatial query (two-pass: point → envelope)
#     → GeoJSON FeatureCollection
#     → outer ring del primer Polygon/MultiPolygon
#     → Google Encoded Polyline Algorithm Format
#     → string para path=enc:... en Google Maps Static API
#
# COVERAGE GAP: solo condados en `Api::LocalGisController::COUNTY_GIS_REGISTRY`
# (6 condados FL al 2026-05-07). Cualquier otro county → return nil → el helper
# `static_map_url` cae al marker fallback. NO es bug, es limitación documentada.
#
# Uso:
#   encoded = ParcelPolygonEncoder.encode_for(parcel)
#   parcel.update_column(:polygon_encoded, encoded) if encoded.present?
#
class ParcelPolygonEncoder
  ENVELOPE_BUFFER = 0.0003   # ±33m, alineado con Api::LocalGisController

  def self.encode_for(parcel)
    new(parcel).call
  end

  def initialize(parcel)
    @parcel = parcel
  end

  def call
    return nil unless gateable?

    config = registry_lookup
    return nil unless config  # condado no soportado — fallback a marker

    ring = fetch_outer_ring(config)
    return nil if ring.blank?

    Polyline.encode(ring)
  rescue StandardError => e
    Rails.logger.warn(
      "[ParcelPolygonEncoder] parcel_id=#{@parcel.id} error=#{e.class}: #{e.message}"
    )
    nil
  end

  private

  def gateable?
    @parcel.latitude.present? &&
      @parcel.longitude.present? &&
      @parcel.county.present? &&
      @parcel.state.present?
  end

  def registry_lookup
    state_up   = @parcel.state.to_s.upcase.strip
    state_abbr = Api::LocalGisController::STATE_ABBREVIATIONS[state_up] || state_up
    key = "#{@parcel.county.to_s.upcase.strip}|#{state_abbr}"
    Api::LocalGisController::COUNTY_GIS_REGISTRY[key]
  end

  def fetch_outer_ring(config)
    lat = @parcel.latitude.to_f
    lng = @parcel.longitude.to_f

    features = arcgis_query(config, lat, lng, :point)
    features = arcgis_query(config, lat, lng, :envelope) if features.empty?
    return nil if features.empty?

    geom = features.first.dig("geometry") || {}
    case geom["type"]
    when "Polygon"
      # GeoJSON Polygon → coordinates: [outer_ring, hole1, hole2, ...]
      # outer_ring → [[lng, lat], [lng, lat], ...]
      Array(geom["coordinates"].first).map { |lng_lat| [lng_lat[1].to_f, lng_lat[0].to_f] }
    when "MultiPolygon"
      # MultiPolygon → coordinates: [polygon1, polygon2, ...]
      # Tomamos el primer polígono → su outer ring.
      first_polygon = Array(geom["coordinates"]).first
      Array(first_polygon&.first).map { |lng_lat| [lng_lat[1].to_f, lng_lat[0].to_f] }
    else
      nil
    end
  end

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

    uri = URI.parse("#{config[:url]}?#{query_params.to_query}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "TaxSaleResources/PolygonEncoder"
    request["Accept"]     = "application/json"

    response = http.request(request)
    return [] unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).fetch("features", [])
  rescue Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError, StandardError => e
    Rails.logger.warn("[ParcelPolygonEncoder] arcgis_query #{mode} failed: #{e.message}")
    []
  end

  # ── Google Encoded Polyline Algorithm Format ────────────────────────────
  # https://developers.google.com/maps/documentation/utilities/polylinealgorithm
  # Implementación inline (no añadimos gem `polylines`).
  module Polyline
    def self.encode(points)
      return "" if points.blank?

      result = +""
      prev_lat = 0
      prev_lng = 0

      points.each do |lat, lng|
        int_lat = (lat.to_f * 1e5).round
        int_lng = (lng.to_f * 1e5).round

        result << encode_signed(int_lat - prev_lat)
        result << encode_signed(int_lng - prev_lng)

        prev_lat = int_lat
        prev_lng = int_lng
      end

      result
    end

    # Encode un valor con signo a la cadena ASCII per Google polyline algorithm.
    def self.encode_signed(value)
      value = value.negative? ? ~(value << 1) : (value << 1)
      buffer = +""
      while value >= 0x20
        buffer << ((0x20 | (value & 0x1f)) + 63).chr
        value >>= 5
      end
      buffer << (value + 63).chr
      buffer
    end
  end
end
