# frozen_string_literal: true

# Procesador para la pestaña "Mercados" — TABLA CRUZADA HORIZONTAL.
#
# Cada fila del Sheet contiene ~170 valores mensuales para un condado.
# Este procesador transpone una fila en N registros RealEstateMonthlyVolume.
#
# Flujo:
#   1. Recibe las fechas parseadas del header (columna C en adelante)
#   2. Para cada fila de datos, busca el CountyMarketStat padre
#   3. Upserta un RealEstateMonthlyVolume por cada celda con valor
#
class MarketVolumeRowProcessor
  def initialize(date_headers, stats = { created: 0, updated: 0, skipped: 0, errors: 0 })
    @date_headers = date_headers  # Array de Date, ya parseado del header fila 3
    @stats = stats
    @county_cache = {}  # Cache de CountyMarketStat por "STATE|COUNTY"
  end

  attr_reader :stats

  def process(row)
    return skip! unless MarketSheetColumnMap.valid_row?(row)

    state  = row[MarketSheetColumnMap::STATE_COL]&.to_s&.strip&.upcase
    county = row[MarketSheetColumnMap::COUNTY_COL]&.to_s&.strip

    # Buscar el condado padre (con cache para performance)
    county_stat = find_county_stat(state, county)
    unless county_stat
      Rails.logger.warn("[MarketVolumeRowProcessor] CountyMarketStat not found for #{state}/#{county}")
      @stats[:skipped] += 1
      return
    end

    # Transponer: cada celda de la columna C en adelante es un mes
    # Wrap en transacción para performance en SQLite (~100x speedup)
    values_start = MarketSheetColumnMap::DATES_START_COL
    monthly_values = row[values_start..] || []

    ActiveRecord::Base.transaction do
      monthly_values.each_with_index do |raw_value, i|
        next if raw_value.blank?

        period_date = @date_headers[i]
        next unless period_date  # Si no hay fecha parseada para esta columna, skip

        amount = sanitize_currency(raw_value)
        next unless amount && amount > 0

        upsert_volume(county_stat, period_date, amount)
      end
    end

  rescue => e
    Rails.logger.error("[MarketVolumeRowProcessor] Error processing row for #{state}/#{county}: #{e.message}")
    @stats[:errors] += 1
  end

  private

  def find_county_stat(state, county)
    # Normalizar: DB tiene state/county en UPPERCASE (del Sheet Condados)
    # pero Mercados usa mixed case y puede tener trailing spaces
    norm_state  = state.to_s.strip.upcase
    norm_county = county.to_s.strip.upcase
    cache_key = "#{norm_state}|#{norm_county}"
    @county_cache[cache_key] ||= CountyMarketStat
      .where("UPPER(TRIM(state)) = ? AND UPPER(TRIM(county)) = ?", norm_state, norm_county)
      .first
  end

  def upsert_volume(county_stat, period_date, amount)
    record = RealEstateMonthlyVolume.find_or_initialize_by(
      county_market_stat: county_stat,
      period_date:        period_date
    )
    is_new = record.new_record?
    record.volume_amount = amount

    if record.save
      @stats[is_new ? :created : :updated] += 1
    else
      @stats[:errors] += 1
    end
  end

  def sanitize_currency(val)
    return nil if val.blank?
    cleaned = val.to_s.gsub(/[$,\s]/, "")
    return nil unless cleaned.match?(/\A-?\d+\.?\d*\z/)
    result = cleaned.to_d
    result.zero? ? nil : result
  end

  def skip!
    @stats[:skipped] += 1
  end
end
