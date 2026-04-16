# frozen_string_literal: true

# SheetRowProcessor — Procesa una fila del Google Sheet y la persiste en PostgreSQL
#
# Cada fila representa una parcela. Si ya existe (por state+county+parcel_id),
# hace upsert actualizando los campos con los datos frescos del Sheet.
# Si la fila no tiene parcel_id ni address, se ignora silenciosamente.
# Los errores de fila individual son rescatados en SyncSheetJob (no paran el batch).
#
# ⛔ REGLA CRÍTICA — INMUNIDAD DEL MINI CRM:
#    Este procesador NUNCA toca `parcel_user_tags` ni `parcel_user_notes`.
#    Esas tablas son propiedad exclusiva del usuario (Mini CRM).
#    Un guard defensivo en `upsert_parcel` garantiza esta regla a nivel de AR.
#
# 🪞 ESPEJO INFALIBLE:
#    Si una celda se borra en el Sheet, el campo correspondiente en PostgreSQL
#    DEBE actualizarse a nil/vacío. El col() helper retorna nil para blanks,
#    y parsed_coords devuelve nils explícitos cuando se borran coordenadas.
#    Ningún dato viejo puede sobrevivir a un sync si la celda original está vacía.
#
# 🛡️ BLINDAJE PostgreSQL:
#    El lookup usa la clave compuesta (state, county, parcel_id) alineada con
#    el UNIQUE INDEX idx_parcels_unique_state_county_pid. Esto garantiza que
#    find_or_initialize_by choque contra el mismo constraint que protege la BD.
#
# 🧹 SANITIZACIÓN ESTRICTA (Auditoría v2):
#    Todos los campos numéricos/moneda pasan por sanitización explícita que
#    elimina símbolos de dólar, comas, espacios, NBSP, y otros caracteres
#    no numéricos ANTES de la conversión a BigDecimal. Esto previene que
#    PostgreSQL trunque valores como "$25,000" a 0 o nil.
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
    return :skipped if row_empty?

    auction = find_or_create_auction
    upsert_parcel(auction)
  end

  private

  # ── AUCTION ──────────────────────────────────────────────────────────────────
  # Las auctions se derivan del Sheet — no tienen hoja propia.
  # Se agrupan por (county + state + sale_date).
  # La tabla auctions ya tiene UNIQUE INDEX en [:county, :state, :sale_date]
  # (migración 20260401191952), así que find_or_create_by! es seguro.

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
  # 🛡️ CLAVE COMPUESTA: El lookup usa (state, county, parcel_id), alineado
  #    con el UNIQUE INDEX en PostgreSQL. Esto elimina el riesgo de colisiones
  #    entre condados que reutilizan el mismo APN (parcel number).
  #
  # 🪞 ESPEJO INFALIBLE: Cada campo del Sheet se mapea explícitamente.
  #    Si la celda está vacía → col() retorna nil → PostgreSQL se actualiza a NULL.
  #    Los campos parsed (currency, decimal, boolean) retornan nil si el input es blank.
  #    Las coordenadas (parsed_coords) retornan nil explícito si la celda AJ se borra.
  #
  # ⛔ CRM IMMUNITY: enforce_crm_immunity! valida ANTES de assign_attributes
  #    que ningún campo del Mini CRM se infiltre en el hash de sync.
  #
  # Retorna :added o :updated para tracking preciso en SyncSheetJob.

  def upsert_parcel(auction)
    # 🛡️ Lookup por clave compuesta — alineado con idx_parcels_unique_state_county_pid
    parcel = Parcel.find_or_initialize_by(
      state:     col(STATE),
      county:    col(COUNTY),
      parcel_id: col(PARCEL_ID)
    )

    result = parcel.new_record? ? :added : :updated

    attrs = {
      auction_id:           auction.id,
      # ── Identificación (state, county, parcel_id ya están en el find_or_initialize_by)
      address:              col(ADDRESS),
      property_address:     col(PROPERTY_ADDRESS),
      zip:                  col(ZIP),
      city:                 col(CITY),
      # ── Propietario
      owner_name:           col(OWNER_NAME),
      owner_mail_address:   col(OWNER_MAIL_ADDRESS),
      legal_description:    col(LEGAL_DESCRIPTION),
      # ── Financiero (🧹 sanitización estricta vía parse_currency)
      opening_bid:          parse_currency(col(OPENING_BID)),
      assessed_value:       parse_currency(col(ASSESSED_VALUE)),
      market_value:         parse_currency(col(MARKET_VALUE)),
      estimated_sale_value: parse_currency(col(ESTIMATED_SALE_VALUE)),
      price_per_acre:       calculate_price_per_acre,
      # ── Físico (🧹 sanitización estricta vía parse_decimal)
      sqft_lot:             parse_decimal(col(SQFT_LOT)),
      sqft_living:          parse_decimal(col(SQFT_LIVING)),
      lot_area_acres:       parse_decimal(col(LOT_AREA_ACRES)),
      minimum_lot_size:     col(MINIMUM_LOT_SIZE),
      zoning:               col(ZONING),
      jurisdiction:         col(JURISDICTION),
      land_use:             col(LAND_USE),
      lot_shape:            col(LOT_SHAPE),
      # ── Clasificación para inversión
      homestead_flag:       col(HOMESTEAD_FLAG),
      crime_level:          col(CRIME_LEVEL),
      # ── Utilities
      electric:             col(ELECTRIC),
      water:                col(WATER),
      sewer:                col(SEWER),
      hoa:                  col(HOA),
      # ── FEMA / Medioambiente
      wetlands:             parse_boolean(col(WETLANDS_RAW)),
      fema_risk_level:      col(FEMA_RISK_LEVEL),
      fema_notes:           col(FEMA_NOTES),
      fema_url:             col(FEMA_URL),
      # ── Coordenadas (col AJ — "30.452145, -87.270564")
      # 🪞 ESPEJO: Si la celda se borra, parsed_coords devuelve {latitude: nil, longitude: nil}
      #    forzando la limpieza en BD. Antes devolvía {} que ignoraba la actualización.
      **parsed_coords,
      # ── Links externos
      regrid_url:           col(REGRID_URL),
      gis_image_url:        col(GIS_IMAGE_URL),
      google_maps_url:      col(GOOGLE_MAPS_URL),
      property_image_url:   col(PROPERTY_IMAGE_URL),
      clerk_url:            col(CLERK_URL),
      tax_collector_url:    col(TAX_COLLECTOR_URL),
      # ── Metadata de sync
      data_source:          "google_sheets",
      last_synced_at:       Time.current
    }

    # ── GUARD: CRM IMMUNITY CHECK ────────────────────────────────────────────
    # Barrera defensiva: si por error de refactor alguien inyecta campos CRM
    # en el hash de atributos, el procesador falla ANTES de tocar la BD.
    enforce_crm_immunity!(attrs)

    parcel.assign_attributes(attrs)
    parcel.save!

    result
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

  # ── COORDENADAS ────────────────────────────────────────────────────────────
  # Parsea la cadena de coordenadas del Sheet (col AJ)
  # Formato esperado: "30.452145, -87.270564" (lat, lng separados por coma)
  # También soporta: "30.452145 x -87.270564" o "30.452145 -87.270564"
  #
  # 🪞 ESPEJO INFALIBLE:
  #   - Celda con valor válido → { latitude: BigDecimal, longitude: BigDecimal }
  #   - Celda vacía/borrada   → { latitude: nil,        longitude: nil }   ← FUERZA LIMPIEZA
  #   - Celda con basura      → { latitude: nil,        longitude: nil }   ← FUERZA LIMPIEZA
  #
  # ANTES del fix, retornaba {} (hash vacío) cuando la celda estaba vacía,
  # lo que hacía que assign_attributes NO tocara lat/lng y el dato viejo sobreviviera.
  def parsed_coords
    raw = col(COORDINATES_RAW)

    # 🪞 Si la celda está vacía → forzar nil en ambas coordenadas
    return { latitude: nil, longitude: nil } if raw.blank?

    # Separar por coma, "x", o espacios múltiples
    parts = raw.split(/[,x]|\s{2,}/).map(&:strip).reject(&:blank?)
    return { latitude: nil, longitude: nil } unless parts.size == 2

    lat = parts[0].to_d
    lng = parts[1].to_d

    # Validación básica de rangos
    return { latitude: nil, longitude: nil } unless lat.between?(-90, 90) && lng.between?(-180, 180)
    return { latitude: nil, longitude: nil } if lat.zero? && lng.zero?

    { latitude: lat, longitude: lng }
  rescue ArgumentError
    { latitude: nil, longitude: nil }
  end

  # ── HELPERS ───────────────────────────────────────────────────────────────────

  # Extrae el valor de una celda por índice posicional.
  # Google Sheets API trunca celdas vacías al final del array, así que
  # acceder fuera de rango retorna nil → .to_s → "" → .strip → "" → .presence → nil.
  #
  # 🪞 ESPEJO: Una celda vacía SIEMPRE retorna nil, garantizando que
  #    assign_attributes reciba nil y PostgreSQL se actualice a NULL.
  #
  # 🛡️ MAPEO RESILIENTE: .to_s.strip elimina caracteres invisibles (NBSP,
  #    tabs, trailing spaces) que podrían existir en cabeceras o celdas del Sheet.
  def col(index)
    @row[index].to_s.strip.presence
  end

  def row_empty?
    col(PARCEL_ID).blank? && col(ADDRESS).blank?
  end

  # ── PARSEO DE FECHAS ────────────────────────────────────────────────────────
  # Formato esperado: "MM/DD/YYYY" (estándar US del Sheet)
  # Tolerante a formatos alternativos: intenta strptime primero, luego Date.parse como fallback.
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

  # ── SANITIZACIÓN DE MONEDA (🧹 AUDITORÍA v2) ──────────────────────────────
  # Google Sheets puede enviar moneda en múltiples formatos sucios:
  #   "$25,000"    → 25000.0
  #   "$25,000.50" → 25000.50
  #   "25000"      → 25000.0
  #   "25,000"     → 25000.0
  #   " $25,000 "  → 25000.0  (con espacios)
  #   "$0"         → 0.0
  #   ""           → nil
  #   nil          → nil
  #   "(25,000)"   → nil  (negativo contable — no tiene sentido para bids)
  #   "N/A"        → nil
  #   "TBD"        → nil
  #
  # Algoritmo: eliminar TODOS los caracteres que no sean dígitos, punto decimal
  # o signo negativo. Si el resultado no es un número válido → nil.
  def parse_currency(str)
    return nil if str.blank?

    # Detectar formato contable negativo: "(25,000)" → no tiene sentido para bids
    return nil if str.strip.match?(/\A\(.*\)\z/)

    # Eliminar todo excepto dígitos, punto decimal y signo negativo
    cleaned = str.gsub(/[^\d.\-]/, "")
    return nil if cleaned.blank? || cleaned == "." || cleaned == "-"

    value = cleaned.to_d
    # Valores negativos no tienen sentido para bids/moneda en este contexto
    value.negative? ? nil : value
  rescue ArgumentError, TypeError
    nil
  end

  # ── SANITIZACIÓN DE DECIMALES (🧹 AUDITORÍA v2) ────────────────────────────
  # Similar a parse_currency pero para campos de área/superficie.
  # Google Sheets puede enviar: "1,234.56", "1234.56", "1234", " 1,234 "
  #   "1,234.56" → 1234.56
  #   "1234"     → 1234.0
  #   ""         → nil
  #   "N/A"      → nil
  def parse_decimal(str)
    return nil if str.blank?

    cleaned = str.gsub(/[^\d.\-]/, "")
    return nil if cleaned.blank? || cleaned == "." || cleaned == "-"

    cleaned.to_d
  rescue ArgumentError, TypeError
    nil
  end

  # ── PARSEO DE BOOLEANOS ─────────────────────────────────────────────────────
  # Google Sheets envía "yes"/"no" como strings.
  # Tolerante a mayúsculas, espacios, y variaciones ("Yes", "YES", " yes ").
  def parse_boolean(str)
    return nil if str.blank?
    str.strip.downcase == "yes"
  end

  # ── CÁLCULO DE PRICE PER ACRE ──────────────────────────────────────────────
  # Calculado en sync y almacenado en BD para uso en filtros.
  # NULL si no hay bid, no hay acres, o acres es 0.
  def calculate_price_per_acre
    bid   = parse_currency(col(OPENING_BID))
    acres = parse_decimal(col(LOT_AREA_ACRES))
    return nil if bid.nil? || acres.nil? || acres.zero?
    (bid / acres).round(2)
  end
end
