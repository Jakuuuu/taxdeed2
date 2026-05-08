# frozen_string_literal: true

# ClearToBidHelper — Rama 6 (Clear-to-Bid Catalog) view helpers.
#
# Responsibilities:
#   • Build Google Maps Static API URLs (server-side; key never reaches JS).
#   • Map analyst grade ('optimo' | 'viable' | 'deficiente') → Tailwind classes.
#
# SECURITY (CLAUDE.md §3 — Google Maps key handling)
# ─────────────────────────────────────────────────────────────────────────
#   `static_map_url` reads ENV['GOOGLE_MAPS_API_KEY'] server-side and bakes
#   it into the URL that ends up as <img src="…&key=XXX">. The key IS visible
#   to the browser — that is acceptable IFF, and ONLY IFF, the GCP Console has
#   HTTP Referrer restrictions configured for:
#     • cloud.taxsaleresources.com/*
#     • localhost:3000/*  (dev only)
#   plus API restrictions limited to the Maps Static API (and the JS / Street
#   View / Geocoding APIs already in use). Sin esas restricciones la key es
#   exfiltrable.
# ─────────────────────────────────────────────────────────────────────────
module ClearToBidHelper
  STATIC_MAP_BASE = "https://maps.googleapis.com/maps/api/staticmap"

  # Lion brand orange (Regla Naranja #E67E22) usado SOLO para el polígono
  # del parcel en la foto estática (señalización visual del lote).
  # Format esperado por Google: 0xRRGGBBAA.
  POLYGON_STROKE_COLOR = "0xE67E22ff" # solid orange
  POLYGON_FILL_COLOR   = "0xE67E2233" # 20% alpha orange
  MARKER_COLOR         = "0xE67E22"

  # Build a Static Map URL for a given parcel.
  #
  # Tries, in order:
  #   1. Real parcel polygon (encoded polyline) — when parcel exposes
  #      `polygon_encoded` (set by GIS proxy: /api/local_gis/parcel_geometry).
  #   2. Marker at lat/lng with zoom=18 (sane fallback for satellite view).
  #   3. nil → caller renders an "unavailable" placeholder.
  #
  # @param parcel [Parcel, #latitude, #longitude]
  # @param size   [String] "WIDTHxHEIGHT" (default "400x300")
  # @return       [String, nil] fully-qualified URL, or nil if no key / coords.
  def static_map_url(parcel, size: "400x300")
    api_key = ENV["GOOGLE_MAPS_API_KEY"]
    return nil if api_key.blank?
    return nil if parcel.nil?

    params = {
      size:    size,
      maptype: "satellite",
      scale:   2, # retina
      key:     api_key
    }

    # ── 1) Real polygon path (preferred when GIS proxy returned geometry) ──
    # TODO(GIS-PROXY): cuando @parcel exponga un polygon GeoJSON vía
    #   /api/local_gis/parcel_geometry, encode el ring con el algoritmo
    #   Google Encoded Polyline (vendored o gem `polylines`) y guárdalo en
    #   `parcel.polygon_encoded`. Hasta que eso aterrice, fall through al
    #   marker fallback abajo.
    encoded = parcel.respond_to?(:polygon_encoded) ? parcel.polygon_encoded : nil
    if encoded.present?
      params[:path] = "color:#{POLYGON_STROKE_COLOR}|" \
                      "weight:3|" \
                      "fillcolor:#{POLYGON_FILL_COLOR}|" \
                      "enc:#{encoded}"
      return "#{STATIC_MAP_BASE}?#{params.to_query}"
    end

    # ── 2) Marker fallback — requires lat/lng ──────────────────────────────
    lat = parcel.try(:latitude)
    lng = parcel.try(:longitude)
    return nil if lat.blank? || lng.blank?

    params[:zoom]    = 18
    params[:center]  = "#{lat},#{lng}"
    params[:markers] = "color:#{MARKER_COLOR}|#{lat},#{lng}"
    "#{STATIC_MAP_BASE}?#{params.to_query}"
  end

  # Generic, low-resolution regional map for the teaser cards.
  # Centers on the county/state level so we never leak the precise parcel
  # location to non-Premier users. Falls back to a generic US view.
  # `teaser` puede ser un Hash (skeleton payload) o un Parcel.
  def teaser_placeholder_map_url(teaser)
    api_key = ENV["GOOGLE_MAPS_API_KEY"]
    return nil if api_key.blank?

    county = teaser.is_a?(Hash) ? teaser[:county] : teaser.try(:county)
    state  = teaser.is_a?(Hash) ? teaser[:state]  : teaser.try(:state)

    center = [county, state, "USA"].compact.reject(&:blank?).join(", ")
    params = {
      size:    "400x300",
      maptype: "roadmap",
      zoom:    9,
      scale:   2,
      center:  center.presence || "USA",
      key:     api_key
    }
    "#{STATIC_MAP_BASE}?#{params.to_query}"
  end

  # Tailwind classes for the analyst-grade badge.
  def grade_badge_classes(grade)
    case grade.to_s.downcase
    when "optimo"     then "bg-green-100 text-green-800"
    when "viable"     then "bg-yellow-100 text-yellow-800"
    when "deficiente" then "bg-red-100 text-red-800"
    else                   "bg-gray-100 text-gray-800"
    end
  end

  # Solid-color dot inside the badge (matches semantic color).
  def grade_dot_class(grade)
    case grade.to_s.downcase
    when "optimo"     then "bg-green-500"
    when "viable"     then "bg-yellow-500"
    when "deficiente" then "bg-red-500"
    else                   "bg-gray-400"
    end
  end

  # Human label (es) para el grade.
  def grade_label(grade)
    case grade.to_s.downcase
    when "optimo"     then "Óptimo"
    when "viable"     then "Viable"
    when "deficiente" then "Deficiente"
    else                   "Sin clasificar"
    end
  end
end
