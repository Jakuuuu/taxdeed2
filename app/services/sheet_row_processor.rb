# frozen_string_literal: true

# SheetRowProcessor — Procesa una fila del Google Sheet y la persiste en PostgreSQL
#
# Cada fila representa una parcela. Si ya existe (por parcel_id), hace upsert.
# Si la fila no tiene parcel_id ni address, se ignora silenciosamente.
# Los errores de fila individual son rescatados en SyncSheetJob (no paran el batch).
#
# ⛔ REGLA CRÍTICA — INMUNIDAD DEL MINI CRM:
#    Este procesador NUNCA toca `parcel_user_tags` ni `parcel_user_notes`.
#    Esas tablas son propiedad exclusiva del usuario (Mini CRM).
#    Un guard defensivo en `upsert_parcel` garantiza esta regla a nivel de AR.
#
class SheetRowProcessor
  include SheetColumnMap

  # ── CRM IMMUNITY ─────────────────────────────────────────────────────────────
  # Columnas/atributos que el sync masivo NUNCA debe tocar.
  # Si algún atributo de esta lista aparece en el hash de assign_attributes,
  # el procesador levanta un error inmediato para prevenir corrupción de datos CRM.
  CRM_IMMUNE_COLUMNS = %w[
    parcel_user_tags
    parcel_user_notes
    user_tags
    user_notes
  ].freeze

  def self.process(row)
    new(row).call
  end

  def initialize(row)
    @row = row
  end

  def call
    return if row_empty?

    auction = find_or_create_auction
    upsert_parcel(auction)
  end

  private

  # ── AUCTION ──────────────────────────────────────────────────────────────────
  # Las auctions se derivan del Sheet — no tienen hoja propia.
  # Se agrupan por (county + state + sale_date).

  def find_or_create_auction
    Auction.find_or_create_by!(
      county:    col(COUNTY),
      state:     col(STATE),
      sale_date: parse_date(col(AUCTION_DATE))
    ) do |a|
      a.auction_type = "tax_deed"
      a.status       = "upcoming"
    end
  end

  # ── PARCEL ────────────────────────────────────────────────────────────────────

  def upsert_parcel(auction)
    parcel = Parcel.find_or_initialize_by(parcel_id: col(PARCEL_ID))

    attrs = {
      auction_id:           auction.id,
      # Identificación
      address:              col(ADDRESS),
      property_address:     col(PROPERTY_ADDRESS),
      state:                col(STATE),
      county:               col(COUNTY),
      zip:                  col(ZIP),
      city:                 col(CITY),
      # Propietario
      owner_name:           col(OWNER_NAME),
      owner_mail_address:   col(OWNER_MAIL_ADDRESS),
      legal_description:    col(LEGAL_DESCRIPTION),
      # Financiero
      opening_bid:          parse_currency(col(OPENING_BID)),
      assessed_value:       parse_currency(col(ASSESSED_VALUE)),
      market_value:         parse_currency(col(MARKET_VALUE)),
      estimated_sale_value: parse_currency(col(ESTIMATED_SALE_VALUE)),
      price_per_acre:       calculate_price_per_acre,
      # Físico
      sqft_lot:             parse_decimal(col(SQFT_LOT)),
      sqft_living:          parse_decimal(col(SQFT_LIVING)),
      lot_area_acres:       parse_decimal(col(LOT_AREA_ACRES)),
      minimum_lot_size:     col(MINIMUM_LOT_SIZE),
      zoning:               col(ZONING),
      jurisdiction:         col(JURISDICTION),
      land_use:             col(LAND_USE),
      lot_shape:            col(LOT_SHAPE),
      # Inversión
      homestead_flag:       col(HOMESTEAD_FLAG),
      crime_level:          col(CRIME_LEVEL),
      # Utilities
      electric:             col(ELECTRIC),
      water:                col(WATER),
      sewer:                col(SEWER),
      hoa:                  col(HOA),
      # FEMA / Medioambiente
      wetlands:             parse_boolean(col(WETLANDS_RAW)),
      fema_risk_level:      col(FEMA_RISK_LEVEL),
      fema_notes:           col(FEMA_NOTES),
      fema_url:             col(FEMA_URL),
      # Coordenadas (col AJ — "30.452145, -87.270564")
      **parsed_coords,
      # Links externos
      regrid_url:           col(REGRID_URL),
      gis_image_url:        col(GIS_IMAGE_URL),
      google_maps_url:      col(GOOGLE_MAPS_URL),
      property_image_url:   col(PROPERTY_IMAGE_URL),
      clerk_url:            col(CLERK_URL),
      tax_collector_url:    col(TAX_COLLECTOR_URL),
      # Metadata de sync
      data_source:          "google_sheets",
      last_synced_at:       Time.current
    }

    # ── GUARD: CRM IMMUNITY CHECK ────────────────────────────────────────────
    # Barrera defensiva: si por error de refactor alguien inyecta campos CRM
    # en el hash de atributos, el procesador falla ANTES de tocar la BD.
    enforce_crm_immunity!(attrs)

    parcel.assign_attributes(attrs)
    parcel.save!
  end

  # Levanta un error fatal si el hash de atributos contiene campos protegidos
  # del Mini CRM. Esto previene que un sync masivo corrompa datos del usuario.
  def enforce_crm_immunity!(attributes)
    attr_keys = attributes.keys.map(&:to_s)
    violations = attr_keys & CRM_IMMUNE_COLUMNS
    return if violations.empty?

    raise ActiveRecord::RecordNotSaved,
          "[CRM IMMUNITY VIOLATION] SyncSheetJob intentó escribir columnas protegidas del Mini CRM: " \
          "#{violations.join(', ')}. Operación abortada para proteger datos del usuario."
  end

  # Parsea la cadena de coordenadas del Sheet (col AJ)
  # Formato esperado: "30.452145, -87.270564" (lat, lng separados por coma)
  # También soporta: "30.452145 x -87.270564" o "30.452145 -87.270564"
  # @return [Hash] { latitude: BigDecimal, longitude: BigDecimal } o {}
  def parsed_coords
    raw = col(COORDINATES_RAW)
    return {} if raw.blank?

    # Separar por coma, "x", o espacios múltiples
    parts = raw.split(/[,x]|\s{2,}/).map(&:strip).reject(&:blank?)
    return {} unless parts.size == 2

    lat = parts[0].to_d
    lng = parts[1].to_d

    # Validación básica de rangos
    return {} unless lat.between?(-90, 90) && lng.between?(-180, 180)
    return {} if lat.zero? && lng.zero?

    { latitude: lat, longitude: lng }
  rescue ArgumentError
    {}
  end

  # ── HELPERS ───────────────────────────────────────────────────────────────────

  def col(index)
    @row[index].to_s.strip.presence
  end

  def row_empty?
    col(PARCEL_ID).blank? && col(ADDRESS).blank?
  end

  def parse_date(str)
    return nil if str.blank?
    Date.strptime(str, "%m/%d/%Y")
  rescue Date::Error, ArgumentError
    nil
  end

  def parse_currency(str)
    return nil if str.blank?
    str.gsub(/[$,\s]/, "").to_d
  rescue StandardError
    nil
  end

  def parse_decimal(str)
    return nil if str.blank?
    str.gsub(",", "").to_d
  rescue StandardError
    nil
  end

  def parse_boolean(str)
    return nil if str.blank?
    str.strip.downcase == "yes"
  end

  def calculate_price_per_acre
    bid   = parse_currency(col(OPENING_BID))
    acres = parse_decimal(col(LOT_AREA_ACRES))
    return nil if bid.nil? || acres.nil? || acres.zero?
    (bid / acres).round(2)
  end
end
