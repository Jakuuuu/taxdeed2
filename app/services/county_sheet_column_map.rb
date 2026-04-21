# frozen_string_literal: true

# Mapa de columnas para la pestaña "Condados" del Google Sheet.
# Mapea posiciones de columna (A=0, B=1...) a atributos del modelo CountyMarketStat.
#
# HEADERS REALES (35 columnas, A-AI):
#   A:  ESTADO                B:  MODALIDAD             C:  CONDADO
#   D:  ACERCA DE             E:  LIMITA                F:  TOP CIUDADES 1
#   G:  TOP CIUDADES 2        H:  TOP CIUDADES 3        I:  GOOGLEMAPS
#   J:  REDFIN                K:  IMAGEN CONDADO        L:  MERCADO
#   M:  CRIMINALIDAD          N:  INUNDACIÓN            O:  CENSUS
#   P:  FRED                  Q:  POBLACIÓN             R:  PBI
#   S:  INGRESO MEDIO         T:  % EMPLEO              U:  % DESEMPLEO
#   V:  MEDIAN HOME           W:  $ x SQFT              X:  LISTADOS ACTIVOS
#   Y:  DAYS ON MARKET        Z:  REALTOR               AA: CRECIMIENTO ANUAL
#   AB: PRESUPUESTO ANUAL     AC: BUDGETS               AD: BEA
#   AE: FAQ                   AF: PLANNING & ZONING     AG: BUILDING DIVISION
#   AH: CLERK OFFICE          AI: TAX COLLECTOR
#
class CountySheetColumnMap
  # Columnas → posiciones (0-indexed)
  MAP = {
    state:                     0,   # A: ESTADO
    modalidad:                 1,   # B: MODALIDAD
    county:                    2,   # C: CONDADO
    about:                     3,   # D: ACERCA DE
    borders:                   4,   # E: LIMITA
    city_1:                    5,   # F: TOP CIUDADES 1
    city_2:                    6,   # G: TOP CIUDADES 2
    city_3:                    7,   # H: TOP CIUDADES 3
    google_maps_url:           8,   # I: GOOGLEMAPS
    redfin_url:                9,   # J: REDFIN
    county_image_url:         10,   # K: IMAGEN CONDADO
    market_status:            11,   # L: MERCADO
    crime_rating:             12,   # M: CRIMINALIDAD
    flood_risk:               13,   # N: INUNDACIÓN
    census_url:               14,   # O: CENSUS
    fred_url:                 15,   # P: FRED
    population:               16,   # Q: POBLACIÓN
    gdp:                      17,   # R: PBI
    median_household_income:  18,   # S: INGRESO MEDIO
    employment_rate:          19,   # T: % EMPLEO
    unemployment_rate:        20,   # U: % DESEMPLEO
    median_home_price:        21,   # V: MEDIAN HOME
    price_per_sqft:           22,   # W: $ x SQFT
    active_listings:          23,   # X: LISTADOS ACTIVOS
    days_on_market:           24,   # Y: DAYS ON MARKET
    realtor_url:              25,   # Z: REALTOR
    annual_growth_rate:       26,   # AA: CRECIMIENTO ANUAL
    annual_budget:            27,   # AB: PRESUPUESTO ANUAL
    budgets_url:              28,   # AC: BUDGETS
    bea_url:                  29,   # AD: BEA
    faq_url:                  30,   # AE: FAQ
    planning_zoning_contact:  31,   # AF: PLANNING & ZONING
    building_division_contact: 32,  # AG: BUILDING DIVISION
    clerk_office_contact:     33,   # AH: CLERK OFFICE
    tax_collector_contact:    34,   # AI: TAX COLLECTOR
  }.freeze

  # Headers reales para validación (validate_headers!)
  REQUIRED_HEADERS = {
    0  => "ESTADO",
    2  => "CONDADO",
    11 => "MERCADO",
    16 => "POBLACIÓN",
    21 => "MEDIAN HOME",
  }.freeze

  TAB_NAME = "Condados"

  # Rango mínimo: A a AI (columna 35)
  DATA_START_ROW = 2   # Los datos empiezan en fila 2 (fila 1 es header)
  COLUMN_RANGE  = "A:AI"

  def self.get(row, field)
    idx = MAP[field]
    return nil unless idx
    row[idx]&.to_s&.strip
  end

  def self.valid_row?(row)
    state  = get(row, :state)
    county = get(row, :county)
    state.present? && county.present?
  end
end
