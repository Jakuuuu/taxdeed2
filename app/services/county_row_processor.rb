# frozen_string_literal: true

# Procesador de filas para la pestaña "Condados".
# Upsert de CountyMarketStat usando clave compuesta (state, county).
#
# Maneja:
# - Sanitización de moneda ($1,234.56 → 1234.56)
# - Sanitización de porcentajes (58.9% → 58.9)
# - Sanitización de población (278, 468 → 278468)
# - Hyperlinks reales del Sheet (extraídos vía spreadsheets.get API)
# - Contactos institucionales (emails y phones como strings)
#
# 🔗 HYPERLINKS:
#   Las celdas del Sheet con hiperenlaces embebidos muestran "Link" como
#   texto visible, pero la URL real está en los metadatos de la celda.
#   Se extraen vía GoogleSheetsImporter.fetch_county_hyperlinks y se pasan
#   como un Hash: { col_index => "https://real-url.com" }
#
class CountyRowProcessor
  # Columnas que contienen hyperlinks embebidos en el Sheet.
  # Mapa: campo del modelo → posición de columna en el Sheet (0-indexed).
  URL_FIELDS = {
    google_maps_url:  CountySheetColumnMap::MAP[:google_maps_url],   # 8  (I)
    redfin_url:       CountySheetColumnMap::MAP[:redfin_url],        # 9  (J)
    county_image_url: CountySheetColumnMap::MAP[:county_image_url],  # 10 (K)
    census_url:       CountySheetColumnMap::MAP[:census_url],        # 14 (O)
    fred_url:         CountySheetColumnMap::MAP[:fred_url],          # 15 (P)
    realtor_url:      CountySheetColumnMap::MAP[:realtor_url],       # 25 (Z)
    budgets_url:      CountySheetColumnMap::MAP[:budgets_url],       # 28 (AC)
    bea_url:          CountySheetColumnMap::MAP[:bea_url],           # 29 (AD)
    faq_url:          CountySheetColumnMap::MAP[:faq_url],           # 30 (AE)
  }.freeze

  def initialize(stats = { created: 0, updated: 0, skipped: 0, errors: 0 })
    @stats = stats
  end

  attr_reader :stats

  # @param row [Array] fila de datos del Sheet (plain text values)
  # @param row_hyperlinks [Hash, nil] hyperlinks para esta fila: { col_index => url }
  def process(row, row_hyperlinks: nil)
    return skip! unless CountySheetColumnMap.valid_row?(row)

    state  = get(row, :state)&.upcase&.strip
    county = get(row, :county)&.strip

    attrs = {
      modalidad:                 get(row, :modalidad),
      about:                     get(row, :about),
      borders:                   get(row, :borders),
      city_1:                    get(row, :city_1),
      city_2:                    get(row, :city_2),
      city_3:                    get(row, :city_3),
      # ── URL fields: prefer hyperlink, fallback to text ──────────────────
      google_maps_url:           resolve_url(row, :google_maps_url, row_hyperlinks),
      redfin_url:                resolve_url(row, :redfin_url, row_hyperlinks),
      county_image_url:          resolve_url(row, :county_image_url, row_hyperlinks),
      census_url:                resolve_url(row, :census_url, row_hyperlinks),
      fred_url:                  resolve_url(row, :fred_url, row_hyperlinks),
      realtor_url:               resolve_url(row, :realtor_url, row_hyperlinks),
      budgets_url:               resolve_url(row, :budgets_url, row_hyperlinks),
      bea_url:                   resolve_url(row, :bea_url, row_hyperlinks),
      faq_url:                   resolve_url(row, :faq_url, row_hyperlinks),
      # ── Regular fields ─────────────────────────────────────────────────
      market_status:             get(row, :market_status),
      crime_rating:              get(row, :crime_rating),
      flood_risk:                get(row, :flood_risk),
      population:                sanitize_integer(get(row, :population)),
      gdp:                       sanitize_currency(get(row, :gdp)),
      median_household_income:   sanitize_currency(get(row, :median_household_income)),
      employment_rate:           sanitize_percentage(get(row, :employment_rate)),
      unemployment_rate:         sanitize_percentage(get(row, :unemployment_rate)),
      median_home_price:         sanitize_currency(get(row, :median_home_price)),
      price_per_sqft:            sanitize_currency(get(row, :price_per_sqft)),
      active_listings:           sanitize_integer(get(row, :active_listings)),
      days_on_market:            sanitize_integer(get(row, :days_on_market)),
      annual_growth_rate:        sanitize_percentage(get(row, :annual_growth_rate)),
      annual_budget:             sanitize_currency(get(row, :annual_budget)),
      planning_zoning_contact:   get(row, :planning_zoning_contact),
      building_division_contact: get(row, :building_division_contact),
      clerk_office_contact:      get(row, :clerk_office_contact),
      tax_collector_contact:     get(row, :tax_collector_contact),
    }

    record = CountyMarketStat.find_or_initialize_by(state: state, county: county)
    is_new = record.new_record?
    record.assign_attributes(attrs)

    if record.save
      @stats[is_new ? :created : :updated] += 1
    else
      Rails.logger.warn("[CountyRowProcessor] Validation failed for #{state}/#{county}: #{record.errors.full_messages.join(', ')}")
      @stats[:errors] += 1
    end

  rescue => e
    Rails.logger.error("[CountyRowProcessor] Error processing row: #{e.message}")
    @stats[:errors] += 1
  end

  private

  def get(row, field)
    CountySheetColumnMap.get(row, field)
  end

  # Resolve a URL field: use hyperlink from cell metadata if available,
  # otherwise fall back to text value (only if it looks like a real URL).
  def resolve_url(row, field, row_hyperlinks)
    col_idx = URL_FIELDS[field]

    # Try hyperlink first
    if row_hyperlinks && col_idx && row_hyperlinks[col_idx].present?
      return row_hyperlinks[col_idx]
    end

    # Fallback: use text value only if it's a real URL (not "Link" or "imagen")
    text = get(row, field)
    return text if text.present? && text.match?(%r{\Ahttps?://}i)

    nil
  end

  def skip!
    @stats[:skipped] += 1
  end

  # "$1,234,567.89" → 1234567.89
  def sanitize_currency(val)
    return nil if val.blank?
    cleaned = val.to_s.gsub(/[$,\s]/, "")
    return nil unless cleaned.match?(/\A-?\d+\.?\d*\z/)
    cleaned.to_d
  end

  # "58.9%" → 58.9 | "5.3 %" → 5.3
  def sanitize_percentage(val)
    return nil if val.blank?
    cleaned = val.to_s.gsub(/[%\s]/, "")
    return nil unless cleaned.match?(/\A-?\d+\.?\d*\z/)
    cleaned.to_d
  end

  # "278, 468" → 278468 | "1,799" → 1799
  def sanitize_integer(val)
    return nil if val.blank?
    cleaned = val.to_s.gsub(/[,\s]/, "")
    return nil unless cleaned.match?(/\A-?\d+\z/)
    cleaned.to_i
  end
end
