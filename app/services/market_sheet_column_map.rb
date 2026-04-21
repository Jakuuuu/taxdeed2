# frozen_string_literal: true

# Mapa de columnas para la pestaña "Mercados" del Google Sheet.
#
# ┌──────────────────────────────────────────────────────────────────┐
# │ ESTRUCTURA REAL DEL SHEET (TABLA CRUZADA HORIZONTAL)            │
# │                                                                  │
# │ Fila 1: ( vacío ) | ( vacío ) | "Mes de Period End"             │
# │ Fila 2: ( vacía )                                               │
# │ Fila 3: "Estado" | "Condados" | "Enero de 2012" | "Feb..." | … │
# │ Fila 4: "Florida"| "Alachua"  | "$164,950.00"   | "$196..."| … │
# │ ...                                                              │
# │ Fila 72: "Florida"| "Wakulla" | "$120,000.00"   | ...      | … │
# │                                                                  │
# │ Total: 172 columnas (2 id + 170 meses), 70 filas con datos     │
# │ Rango temporal: Enero 2012 → Febrero 2026                       │
# └──────────────────────────────────────────────────────────────────┘
#
# El pipeline lee fila 3 como header de fechas, y transpone cada fila
# de datos (4+) en ~170 registros de RealEstateMonthlyVolume.
#
class MarketSheetColumnMap
  # Posiciones fijas (las columnas de datos son dinámicas)
  STATE_COL  = 0  # A: Estado
  COUNTY_COL = 1  # B: Condados (nombre del condado)
  DATES_START_COL = 2  # C en adelante: valores mensuales

  TAB_NAME = "Mercados"

  # Los datos reales empiezan en fila 4 del Sheet (fila 3 = headers de fechas)
  HEADER_ROW    = 3   # Fila del Sheet con los nombres de mes
  DATA_START_ROW = 4  # Primera fila con datos de condado

  # Formato de las fechas en el header: "Enero de 2012", "Febrero de 2012", etc.
  MONTH_NAMES_ES = {
    "Enero"      => 1, "Febrero"    => 2, "Marzo"      => 3,
    "Abril"      => 4, "Mayo"       => 5, "Junio"      => 6,
    "Julio"      => 7, "Agosto"     => 8, "Septiembre" => 9,
    "Octubre"    => 10, "Noviembre" => 11, "Diciembre" => 12,
  }.freeze

  # Parsea "Enero de 2012" → Date(2012, 1, 1)
  def self.parse_month_header(header_str)
    return nil if header_str.blank?
    match = header_str.strip.match(/\A(\w+)\s+de\s+(\d{4})\z/i)
    return nil unless match

    month_name = match[1].capitalize
    year       = match[2].to_i
    month_num  = MONTH_NAMES_ES[month_name]
    return nil unless month_num

    Date.new(year, month_num, 1)
  end

  # Valida que la fila de headers tiene la estructura esperada
  REQUIRED_HEADERS = {
    0 => "Estado",
    1 => "Condados",
  }.freeze

  def self.valid_row?(row)
    state  = row[STATE_COL]&.to_s&.strip
    county = row[COUNTY_COL]&.to_s&.strip
    state.present? && county.present?
  end
end
