# frozen_string_literal: true

# Api::LocalGisController — Proxy server-side para ArcGIS REST endpoints de condados
#
# Propósito:
#   Reemplaza Regrid como fuente de geometrías de parcelas. Consulta directamente
#   los servidores ArcGIS REST públicos de cada condado usando spatial queries
#   (punto ➜ polígono intersectado), elimina la dependencia de tokens pagados.
#
# Estrategia (Two-Pass Spatial Query):
#   1. Primero intenta esriGeometryPoint (hit exacto — punto dentro del polígono).
#   2. Si retorna 0 features (coords geocodificadas caen en la calle o lote
#      vecino), reintenta con esriGeometryEnvelope y un buffer de ±0.0003°
#      (~33m), que captura la parcela más cercana.
#   Esto es más confiable que buscar por APN (evita problemas de formato de
#   PCN entre condados) y tolera imprecisión de geocoding.
#
# Ruta:
#   GET /api/local_gis/parcel_geometry?lat=..&lng=..&county=..&state=..
#
# Seguridad:
#   - Requiere autenticación (before_action :authenticate_user!)
#   - Sin API tokens que exponer (los endpoints ArcGIS son públicos)
#
# Cache:
#   - Rails.cache compartido: un solo query al condado por parcela,
#     todos los usuarios leen del caché.
#   - TTL dinámico: hasta el día de la subasta + 1d (si se conoce),
#     o 90 días por defecto (los límites de lotes no cambian).
#   - HTTP cache público (CDN-friendly) con el mismo TTL.
#
module Api
  class LocalGisController < ApplicationController
    before_action :authenticate_user!

    # ── Registro de endpoints ArcGIS por condado ──────────────────────────
    # Clave: "COUNTY_NAME|STATE_ABBR" (uppercased)
    # Valor: Hash con :url (query endpoint), :out_fields (campos a solicitar)
    #
    # Para agregar un condado nuevo:
    #   1. Localizar el ArcGIS REST service del condado (MapServer o FeatureServer)
    #   2. Identificar la capa con geometryType: esriGeometryPolygon y atributos de parcela
    #   3. Verificar que soporta Query y f=geojson
    #   4. Agregar la entrada aquí
    #
    COUNTY_GIS_REGISTRY = {
      "PALM BEACH|FL" => {
        url: "https://maps.co.palm-beach.fl.us/arcgis/rest/services/Parcels/labels/MapServer/0/query",
        out_fields: "PAO.PARCELS.PARID,PAO.PARCELS.ACRES,PAO.PROPINFO_PUB.SITE_ADDR_STR"
      },
      "BREVARD|FL" => {
        url: "https://gis.brevardfl.gov/gissrv/rest/services/Base_Map/Parcel_New_WKID2881/MapServer/4/query",
        out_fields: "PARCELID,SITEADDR,ACREAGE"
      },
      "HILLSBOROUGH|FL" => {
        url: "https://gis.hcpafl.org/arcgis/rest/services/Webmaps/HillsboroughFL_WebParcels/MapServer/0/query",
        out_fields: "folio,FullAddress,ShapeArea"
      },
      "MARION|FL" => {
        url: "https://gis.marionfl.org/public/rest/services/General/Parcels/MapServer/0/query",
        out_fields: "PARCEL,SITUS_1,ACRES,SHAPE.STArea()"
      },
      "PUTNAM|FL" => {
        url: "https://pamap.putnam-fl.gov/server/rest/services/CadastralData/FeatureServer/2/query",
        out_fields: "PARCELID,SITEADDRESS,STATEDAREA"
      },
      "WASHINGTON|FL" => {
        url: "https://gis.floridahealth.gov/server/rest/services/EHWATER/Parcels/MapServer/66/query",
        out_fields: "PARCEL_ID,PHY_ADDR1,LND_SQFOOT,SHAPE.STArea()"
      },
      "SARASOTA|FL" => {
        url: "https://services3.arcgis.com/icrWMv7eBkctFu1f/arcgis/rest/services/ParcelHosted/FeatureServer/0/query",
        out_fields: "PARCEL_NO,SITE_ADDR,ACREAGE"
      }
    }.freeze

    # ── Fallback estatal de Florida (FDOR — Florida Dept. of Revenue) ───────
    # Cubre los 67 condados del estado con un esquema uniforme.
    # Se activa automáticamente cuando el condado no tiene entrada propia
    # en COUNTY_GIS_REGISTRY y el estado es Florida ("FL").
    #
    # Endpoint público: ArcGIS Online hosted por FDOR.
    # Campos uniformes en todos los condados:
    #   PARCEL_ID  → Número de parcela del condado
    #   PHY_ADDR1  → Dirección física del predio
    #   LND_SQFOOT → Superficie del lote en pies cuadrados
    FLORIDA_STATEWIDE_GIS = {
      url: "https://services9.arcgis.com/Gh9awoU677aKree0/arcgis/rest/services/Florida_Statewide_Cadastral/FeatureServer/0/query",
      out_fields: "PARCEL_ID,PHY_ADDR1,LND_SQFOOT"
    }.freeze

    # Normalización estado: la DB almacena "Florida", el registry usa "FL".
    # Soporta los 50 estados + DC + territorios comunes.
    STATE_ABBREVIATIONS = {
      "ALABAMA" => "AL", "ALASKA" => "AK", "ARIZONA" => "AZ", "ARKANSAS" => "AR",
      "CALIFORNIA" => "CA", "COLORADO" => "CO", "CONNECTICUT" => "CT", "DELAWARE" => "DE",
      "FLORIDA" => "FL", "GEORGIA" => "GA", "HAWAII" => "HI", "IDAHO" => "ID",
      "ILLINOIS" => "IL", "INDIANA" => "IN", "IOWA" => "IA", "KANSAS" => "KS",
      "KENTUCKY" => "KY", "LOUISIANA" => "LA", "MAINE" => "ME", "MARYLAND" => "MD",
      "MASSACHUSETTS" => "MA", "MICHIGAN" => "MI", "MINNESOTA" => "MN", "MISSISSIPPI" => "MS",
      "MISSOURI" => "MO", "MONTANA" => "MT", "NEBRASKA" => "NE", "NEVADA" => "NV",
      "NEW HAMPSHIRE" => "NH", "NEW JERSEY" => "NJ", "NEW MEXICO" => "NM", "NEW YORK" => "NY",
      "NORTH CAROLINA" => "NC", "NORTH DAKOTA" => "ND", "OHIO" => "OH", "OKLAHOMA" => "OK",
      "OREGON" => "OR", "PENNSYLVANIA" => "PA", "RHODE ISLAND" => "RI", "SOUTH CAROLINA" => "SC",
      "SOUTH DAKOTA" => "SD", "TENNESSEE" => "TN", "TEXAS" => "TX", "UTAH" => "UT",
      "VERMONT" => "VT", "VIRGINIA" => "VA", "WASHINGTON" => "WA", "WEST VIRGINIA" => "WV",
      "WISCONSIN" => "WI", "WYOMING" => "WY", "DISTRICT OF COLUMBIA" => "DC",
      "PUERTO RICO" => "PR", "GUAM" => "GU", "VIRGIN ISLANDS" => "VI"
    }.freeze

    # GET /api/local_gis/parcel_geometry
    def parcel_geometry
      lat    = params[:lat]
      lng    = params[:lng]
      county = params[:county]
      state  = params[:state]

      unless lat.present? && lng.present? && county.present? && state.present?
        render json: { error: "Missing required params: lat, lng, county, state" }, status: :bad_request
        return
      end

      # Sanitizar y validar coordenadas
      lat_f = lat.to_f
      lng_f = lng.to_f

      unless lat_f.between?(-90, 90) && lng_f.between?(-180, 180)
        render json: { error: "Invalid coordinates" }, status: :unprocessable_entity
        return
      end

      # Normalizar estado: acepta "Florida" o "FL" — ambos resuelven a "FL"
      state_up = state.upcase.strip
      state_abbr = STATE_ABBREVIATIONS[state_up] || state_up  # ya es abreviatura? pasar tal cual

      # Buscar endpoint en el registro
      registry_key = "#{county.upcase.strip}|#{state_abbr}"
      config = COUNTY_GIS_REGISTRY[registry_key]

      # Florida statewide fallback: cuando el condado no tiene endpoint propio
      # pero el estado es Florida, usar el FeatureServer estatal del FDOR.
      # Cubre automáticamente los 67 condados (Orange, Duval, Collier, Lee,
      # Polk, Volusia, Pinellas, Miami-Dade, Alachua, etc.).
      if config.nil? && state_abbr == "FL"
        Rails.logger.info "[LocalGIS] No individual endpoint for #{registry_key} — using FL statewide fallback (FDOR)"
        config = FLORIDA_STATEWIDE_GIS
      end

      unless config
        Rails.logger.info "[LocalGIS] No registry entry for #{registry_key} — skipping polygon"
        render json: { type: "FeatureCollection", features: [] }, status: :ok
        return
      end

      # ── Cache compartido (Rails.cache) ──────────────────────────────────
      # Clave basada en coordenadas + condado → todos los usuarios comparten
      # el mismo polígono cacheado. Redondear coords a 6 decimales para
      # normalizar variaciones de precisión insignificantes.
      cache_key = "gis_polygon:#{registry_key}:#{lat_f.round(6)}:#{lng_f.round(6)}"
      cache_ttl = compute_cache_ttl(params[:auction_date])

      geojson = Rails.cache.fetch(cache_key, expires_in: cache_ttl, race_condition_ttl: 5.seconds) do
        Rails.logger.info "[LocalGIS] Cache MISS — querying ArcGIS for #{registry_key} (TTL: #{cache_ttl})"

        # ── Two-Pass Spatial Query ────────────────────────────────────────
        # Pass 1: Punto exacto (esriGeometryPoint) — rápido y preciso
        features = arcgis_spatial_query(config, lat_f, lng_f, :point)

        # Pass 2: Si el punto cae fuera del polígono (geocoding impreciso),
        #         reintentar con un envelope de ±0.0003° (~33m de tolerancia)
        if features.empty?
          Rails.logger.info "[LocalGIS] Point miss for #{registry_key} — retrying with envelope buffer"
          features = arcgis_spatial_query(config, lat_f, lng_f, :envelope)
        end

        Rails.logger.info "[LocalGIS] OK — #{features.size} feature(s) for #{registry_key}"

        { type: "FeatureCollection", features: features }
      end

      # HTTP cache header público — el navegador y CDNs también cachean
      expires_in cache_ttl, public: true

      render json: geojson, status: :ok
    end

    private

    # ── Cache TTL dinámico ─────────────────────────────────────────────────
    # Los polígonos de parcelas son estáticos (los límites del lote no cambian).
    # El TTL se calcula así:
    #   - Con auction_date: cachear hasta el día de la subasta + 1 día de gracia
    #   - Sin auction_date: cachear 90 días (valor conservador por defecto)
    #   - Mínimo 1 hora (floor de seguridad para subastas pasadas)
    DEFAULT_CACHE_TTL = 90.days

    def compute_cache_ttl(auction_date_str)
      return DEFAULT_CACHE_TTL if auction_date_str.blank?

      auction_date = Date.parse(auction_date_str)
      seconds_until = ((auction_date + 1.day).end_of_day - Time.current).to_i
      [seconds_until.seconds, 1.hour].max
    rescue ArgumentError, TypeError
      # Si la fecha es inválida, usar default
      DEFAULT_CACHE_TTL
    end

    # Buffer para envelope fallback: ±0.0003° ≈ ±33 metros en latitudes de Florida.
    # Suficiente para capturar parcelas cuando el geocoding cae en la calle.
    ENVELOPE_BUFFER = 0.0003

    # Ejecuta una spatial query contra ArcGIS REST.
    # mode: :point  → esriGeometryPoint  (hit exacto)
    #        :envelope → esriGeometryEnvelope (bounding box con buffer)
    def arcgis_spatial_query(config, lat, lng, mode)
      query_params = {
        inSR:           "4326",
        outSR:          "4326",
        spatialRel:     "esriSpatialRelIntersects",
        returnGeometry: "true",
        outFields:      config[:out_fields],
        resultRecordCount: "1",
        f:              "geojson"
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

      arcgis_url = "#{config[:url]}?#{query_params.to_query}"

      uri  = URI.parse(arcgis_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl     = true
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "TaxSaleResources/1.0"
      request["Accept"]     = "application/json"

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        geojson = JSON.parse(response.body)
        geojson["features"] || []
      else
        Rails.logger.warn "[LocalGIS] ArcGIS #{mode} query failed: #{response.code}"
        []
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.warn "[LocalGIS] Timeout (#{mode}): #{e.message}"
      []
    rescue JSON::ParserError => e
      # ArcGIS ocasionalmente retorna HTML (502/503 pages) con status 200
      Rails.logger.warn "[LocalGIS] Invalid JSON (#{mode}): #{e.message}"
      []
    rescue StandardError => e
      Rails.logger.error "[LocalGIS] Error (#{mode}): #{e.class}: #{e.message}"
      []
    end
  end
end
