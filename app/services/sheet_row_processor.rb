# frozen_string_literal: true

# SheetRowProcessor — Procesa una fila del Google Sheet y la persiste en PostgreSQL
#
# Cada fila representa una parcela. Si ya existe (por state+county+parcel_id),
# hace upsert actualizando los campos con los datos frescos del Sheet.
# Si la fila no tiene state, county ni parcel_id, se ignora silenciosamente.
# Los errores de fila individual son rescatados en SyncSheetJob (no paran el batch).
#
# ⛔ CRM IMMUNITY:  NUNCA toca parcel_user_tags ni parcel_user_notes.
# 🪞 ESPEJO:        Celda vacía en Sheet → nil en PostgreSQL (obligatorio).
# 🛡️ BLINDAJE:     Lookup por clave compuesta (state, county, parcel_id).
# 🧹 SANITIZACIÓN: Todos los campos pasan por el módulo Sanitize antes de assign_attributes.
#
# 🚀 MEMORY-SAFE (v3):
#   - Acepta auction_cache opcional para evitar N+1 find_or_create_by!
#   - No retiene referencias a objetos Parcel después de save!
#
class SheetRowProcessor
  include SheetColumnMap

  # ⛔ CRM IMMUNITY — Columnas que el sync masivo NUNCA debe tocar
  CRM_IMMUNE_COLUMNS = %w[
    parcel_user_tags
    parcel_user_notes
    user_tags
    user_notes
  ].freeze

  # ── API PÚBLICA ────────────────────────────────────────────────────────────
  # auction_cache: Hash opcional { "state|county|date" => Auction }
  # Provisto por SyncSheetJob para reducir queries de Auction.
  def self.process(row, auction_cache: nil)
    new(row, auction_cache: auction_cache).call
  end

  def initialize(row, auction_cache: nil)
    @row = row
    @auction_cache = auction_cache
  end

  def call
    return :skipped if row_empty?

    auction = find_or_create_auction_cached
    upsert_parcel(auction)
  end

  private

  # ── AUCTION (con cache opcional) ────────────────────────────────────────────
  # Las auctions se derivan del Sheet — no tienen hoja propia.
  # GROUP BY (county + state + sale_date) → find_or_create_by!
  #
  # Si se provee @auction_cache, busca primero ahí para evitar queries
  # repetidas. Típicamente un Sheet tiene ~10-20 auctions únicas pero
  # cientos de parcelas, así que el cache es muy efectivo.
  def find_or_create_auction_cached
    state     = Sanitize.text(col(STATE))
    county    = Sanitize.text(col(COUNTY))
    sale_date = parse_date(col(AUCTION_DATE))
    cache_key = "#{state}|#{county}|#{sale_date}"

    # Si hay cache y la auction ya está cacheada, retornarla
    if @auction_cache
      cached = @auction_cache[cache_key]
      return cached if cached
    end

    auction = Auction.find_or_create_by!(
      county:    county,
      state:     state,
      sale_date: sale_date
    ) do |a|
      a.auction_type = "tax_deed"
      a.status       = "upcoming"
    end

    # Cachear para las siguientes filas del mismo chunk
    @auction_cache[cache_key] = auction if @auction_cache

    auction
  end

  # ── PARCEL ────────────────────────────────────────────────────────────────────
  # 🛡️ Lookup por clave compuesta (state, county, parcel_id)
  # 🪞 Cada campo del Sheet se mapea explícitamente; celda vacía → nil en BD
  # ⛔ enforce_crm_immunity! valida ANTES de assign_attributes
  # 🧹 Cada campo pasa por su limpiador Sanitize.* antes de asignarse
  def upsert_parcel(auction)
    parcel = Parcel.find_or_initialize_by(
      state:     Sanitize.text(col(STATE)),
      county:    Sanitize.text(col(COUNTY)),
      parcel_id: Sanitize.text(col(PARCEL_ID))
    )

    result = parcel.new_record? ? :added : :updated

    attrs = {
      auction_id:           auction.id,

      # ── MONEDA (Sanitize.currency) ────────────────────────────────────
      market_value:         Sanitize.currency(col(MARKET_VALUE)),
      opening_bid:          Sanitize.currency(col(OPENING_BID)),
      assessed_value:       Sanitize.currency(col(ASSESSED_VALUE)),
      estimated_sale_value: Sanitize.currency(col(ESTIMATED_SALE_VALUE)),
      price_per_acre:       calculate_price_per_acre,

      # ── NUMÉRICOS (Sanitize.decimal — alineado con decimal() en PostgreSQL) ──
      lot_area_acres:       Sanitize.decimal(col(LOT_AREA_ACRES)),
      sqft_lot:             Sanitize.decimal(col(SQFT_LOT)),
      sqft_living:          Sanitize.decimal(col(SQFT_LIVING)),

      # ── TEXTO (Sanitize.text) ─────────────────────────────────────────
      address:              Sanitize.text(col(ADDRESS)),
      property_address:     Sanitize.text(col(PROPERTY_ADDRESS)),
      zip:                  Sanitize.text(col(ZIP)),
      city:                 Sanitize.text(col(CITY)),
      legal_description:    Sanitize.text(col(LEGAL_DESCRIPTION)),
      crime_level:          Sanitize.text(col(CRIME_LEVEL)),
      homestead_flag:       Sanitize.text(col(HOMESTEAD_FLAG)),
      land_use:             Sanitize.text(col(LAND_USE)),
      zoning:               Sanitize.text(col(ZONING)),
      jurisdiction:         Sanitize.text(col(JURISDICTION)),
      minimum_lot_size:     Sanitize.text(col(MINIMUM_LOT_SIZE)),
      owner_name:           Sanitize.text(col(OWNER_NAME)),
      owner_mail_address:   Sanitize.text(col(OWNER_MAIL_ADDRESS)),
      lot_shape:            Sanitize.text(col(LOT_SHAPE)),
      fema_notes:           Sanitize.text(col(FEMA_NOTES)),
      fema_risk_level:      Sanitize.text(col(FEMA_RISK_LEVEL)),

      # ── BOOLEANOS (Sanitize.boolean) ──────────────────────────────────
      electric:             Sanitize.boolean(col(ELECTRIC)),
      water:                Sanitize.boolean(col(WATER)),
      sewer:                Sanitize.boolean(col(SEWER)),
      wetlands:             Sanitize.boolean(col(WETLANDS_RAW)),
      hoa:                  Sanitize.boolean(col(HOA)),

      # ── URLs (Sanitize.url) ───────────────────────────────────────────
      regrid_url:           Sanitize.url(col(REGRID_URL)),
      gis_image_url:        Sanitize.url(col(GIS_IMAGE_URL)),
      google_maps_url:      Sanitize.url(col(GOOGLE_MAPS_URL)),
      fema_url:             Sanitize.url(col(FEMA_URL)),
      property_image_url:   Sanitize.url(col(PROPERTY_IMAGE_URL)),
      clerk_url:            Sanitize.url(col(CLERK_URL)),
      tax_collector_url:    Sanitize.url(col(TAX_COLLECTOR_URL)),

      # ── COORDENADAS (parser especial) ─────────────────────────────────
      **parsed_coords,

      # ── METADATA DE SYNC ──────────────────────────────────────────────
      data_source:          "google_sheets",
      last_synced_at:       Time.current
    }

    # ── GUARD: CRM IMMUNITY CHECK ────────────────────────────────────────────
    enforce_crm_immunity!(attrs)

    parcel.assign_attributes(attrs)
    parcel.save!

    result
  end

  # Levanta error fatal si el hash de atributos contiene campos protegidos del Mini CRM
  def enforce_crm_immunity!(attributes)
    violations = attributes.keys.map(&:to_s) & CRM_IMMUNE_COLUMNS
    return if violations.empty?

    raise ActiveRecord::RecordNotSaved,
          "[CRM IMMUNITY VIOLATION] Columnas protegidas: #{violations.join(', ')}"
  end

  # ── COORDENADAS ────────────────────────────────────────────────────────────
  # 🪞 ESPEJO: Celda vacía → { latitude: nil, longitude: nil } (fuerza limpieza)
  # Usa Sanitize.text + Sanitize.coordinate para eliminar caracteres fantasma
  def parsed_coords
    raw = Sanitize.text(col(COORDINATES_RAW))
    return { latitude: nil, longitude: nil } if raw.blank?

    parts = raw.split(/[,x]|\s{2,}/).map(&:strip).reject(&:blank?)
    return { latitude: nil, longitude: nil } unless parts.size == 2

    lat = Sanitize.coordinate(parts[0])
    lng = Sanitize.coordinate(parts[1])

    return { latitude: nil, longitude: nil } if lat.nil? || lng.nil?
    return { latitude: nil, longitude: nil } unless lat.between?(-90, 90) && lng.between?(-180, 180)
    return { latitude: nil, longitude: nil } if lat.zero? && lng.zero?

    { latitude: lat, longitude: lng }
  rescue ArgumentError
    { latitude: nil, longitude: nil }
  end

  # ── HELPERS ───────────────────────────────────────────────────────────────────

  # Extrae el valor crudo de una celda por índice posicional.
  # 🪞 Celda vacía → nil (PostgreSQL se actualiza a NULL)
  def col(index)
    @row[index].to_s.strip.presence
  end

  def row_empty?
    col(STATE).blank? && col(COUNTY).blank? && col(PARCEL_ID).blank?
  end

  def parse_date(str)
    return nil if str.blank?
    Date.strptime(str, "%m/%d/%Y")
  rescue Date::Error, ArgumentError
    begin
      Date.parse(str)
    rescue Date::Error, ArgumentError
      nil
    end
  end

  # Price per acre calculado en sync para uso en filtros
  def calculate_price_per_acre
    bid   = Sanitize.currency(col(OPENING_BID))
    acres = Sanitize.decimal(col(LOT_AREA_ACRES))
    return nil if bid.nil? || acres.nil? || acres.zero?
    (bid / acres).round(2)
  end
end
