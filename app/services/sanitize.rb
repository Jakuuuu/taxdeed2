# frozen_string_literal: true

# Sanitize — Módulo de limpieza estricta para datos del Google Sheet
#
# REGLA: TODO dato del Sheet pasa por un limpiador estático ANTES de
# asignarse a la BD. Cada método es null-safe: recibe nil/"" y retorna nil.
#
# Fuente de verdad: Este archivo (.rb) manda sobre cualquier documentación .md.
#
module Sanitize
  # ── MONEDA ───────────────────────────────────────────────────────────────────
  # Limpia: "$1,234.56" | "$ 1 234.56" | "1234.56USD" → 1234.56
  # Campos: opening_bid, market_value, assessed_value, estimated_sale_value
  def self.currency(val)
    return nil if val.to_s.strip.blank?

    # Detectar formato contable negativo: "(25,000)" — no tiene sentido para bids
    return nil if val.to_s.strip.match?(/\A\(.*\)\z/)

    cleaned = val.to_s.gsub(/[^\d.\-]/, "")
    return nil if cleaned.blank? || cleaned == "." || cleaned == "-"

    value = cleaned.to_d
    value.negative? ? nil : value
  rescue ArgumentError, TypeError
    nil
  end

  # ── TEXTO ────────────────────────────────────────────────────────────────────
  # Mata NBSP (\u00A0), tabs, trailing whitespace, retorna nil si vacío
  # Campos: state, county, parcel_id, property_address, zip, city, etc.
  def self.text(val)
    return nil if val.nil?
    val.to_s.gsub(/\u00A0/, " ").strip.presence
  end

  # ── BOOLEANO ─────────────────────────────────────────────────────────────────
  # Normaliza: "yes"/"Yes"/"YES" → true | "no"/"No"/"NO" → false | otro → nil
  # Campos: electric, water, sewer, wetlands, hoa
  def self.boolean(val)
    return nil if val.to_s.strip.blank?
    case val.to_s.strip.downcase
    when "yes", "y", "true", "1"  then true
    when "no", "n", "false", "0"  then false
    else nil
    end
  end

  # ── ENTERO ───────────────────────────────────────────────────────────────────
  # Limpia: "1,200 sqft" | "1200.00" | "1,200.00" → 1200
  # Campos: sqft_lot, sqft_living
  #
  # ⚠️ FIX v2: El regex anterior /[^\d]/ destruía el punto decimal, causando
  # que "1,200.00" → "120000" (inflación 100x). Ahora se conserva el punto
  # y se parsea como BigDecimal antes de redondear a entero.
  def self.integer(val)
    return nil if val.to_s.strip.blank?
    cleaned = val.to_s.gsub(/[^\d.\-]/, "")
    return nil if cleaned.blank? || cleaned == "." || cleaned == "-"
    cleaned.to_d.round(0).to_i
  rescue ArgumentError, TypeError
    nil
  end

  # ── DECIMAL ──────────────────────────────────────────────────────────────────
  # Limpia: "2.5 acres" | "2,500.75" → 2500.75
  # Campos: lot_area_acres
  def self.decimal(val)
    return nil if val.to_s.strip.blank?
    cleaned = val.to_s.gsub(/[^\d.\-]/, "")
    return nil if cleaned.blank? || cleaned == "." || cleaned == "-"
    cleaned.to_d
  rescue ArgumentError, TypeError
    nil
  end

  # ── URL ──────────────────────────────────────────────────────────────────────
  # Strip + validación mínima de formato (no explota si basura)
  # Campos: regrid_url, gis_image_url, google_maps_url, fema_url, etc.
  def self.url(val)
    cleaned = text(val)
    return nil if cleaned.nil?
    cleaned.start_with?("http://", "https://") ? cleaned : nil
  end

  # ── COORDENADA ────────────────────────────────────────────────────────────────
  # Limpia caracteres fantasma (NBSP, ZWSP, BOM, grado°) y retorna BigDecimal puro.
  # Retorna nil si el valor no es un número válido.
  # Campos: latitude, longitude (vía parsed_coords en SheetRowProcessor)
  def self.coordinate(val)
    return nil if val.nil?

    cleaned = val.to_s
                 .gsub(/[\u00A0\u200B\uFEFF\u200C\u200D\u2060°]/, "") # invisible chars + degree
                 .gsub(/[^\d.\-]/, "")                                 # keep only digits, dot, minus
                 .strip

    return nil if cleaned.blank? || cleaned == "." || cleaned == "-"

    cleaned.to_d
  rescue ArgumentError, TypeError
    nil
  end
end
