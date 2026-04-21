# frozen_string_literal: true

# Migración: county_market_stats — Datos macro de condados para Rama 4 (Market Study)
#
# Clave compuesta: (state, county) — UNIQUE INDEX
# Todos los campos financieros: decimal(15,2) — NUNCA float
# Contactos institucionales: 4 oficinas con email/phone individual
#
# Headers reales del Sheet "Condados" (35 columnas, A-AI):
#   ESTADO, MODALIDAD, CONDADO, ACERCA DE, LIMITA,
#   TOP CIUDADES 1-3, GOOGLEMAPS, REDFIN, IMAGEN CONDADO,
#   MERCADO, CRIMINALIDAD, INUNDACIÓN, CENSUS, FRED,
#   POBLACIÓN, PBI, INGRESO MEDIO, % EMPLEO, % DESEMPLEO,
#   MEDIAN HOME, $ x SQFT, LISTADOS ACTIVOS, DAYS ON MARKET,
#   REALTOR, CRECIMIENTO ANUAL, PRESUPUESTO ANUAL, BUDGETS, BEA,
#   FAQ, PLANNING & ZONING, BUILDING DIVISION, CLERK OFFICE, TAX COLLECTOR
#
class CreateCountyMarketStats < ActiveRecord::Migration[7.2]
  def change
    create_table :county_market_stats do |t|
      # ── Identidad ────────────────────────────────────────────
      t.string :state,       null: false
      t.string :county,      null: false
      t.string :modalidad                    # ONLINE, PRESENCIAL, etc.

      # ── Descripción y geografía ──────────────────────────────
      t.text   :about                        # ACERCA DE (texto largo)
      t.text   :borders                      # LIMITA (condados vecinos)
      t.string :city_1                       # TOP CIUDADES 1
      t.string :city_2                       # TOP CIUDADES 2
      t.string :city_3                       # TOP CIUDADES 3

      # ── Links externos ───────────────────────────────────────
      t.string :google_maps_url              # GOOGLEMAPS link
      t.string :redfin_url                   # REDFIN link
      t.string :county_image_url             # IMAGEN CONDADO
      t.string :census_url                   # CENSUS link
      t.string :fred_url                     # FRED link
      t.string :realtor_url                  # REALTOR link
      t.string :budgets_url                  # BUDGETS link
      t.string :bea_url                      # BEA link
      t.string :faq_url                      # FAQ link

      # ── Indicadores cualitativos ─────────────────────────────
      t.string :market_status                # MERCADO (Activo, Inactivo, etc.)
      t.string :crime_rating                 # CRIMINALIDAD (Riesgo Bajo (B+), etc.)
      t.string :flood_risk                   # INUNDACIÓN (Riego Moderado, etc.)

      # ── Indicadores financieros y demográficos ───────────────
      t.integer :population                  # POBLACIÓN
      t.decimal :gdp,                  precision: 15, scale: 2  # PBI
      t.decimal :median_household_income,    precision: 15, scale: 2  # INGRESO MEDIO
      t.decimal :employment_rate,            precision: 5,  scale: 2  # % EMPLEO
      t.decimal :unemployment_rate,          precision: 5,  scale: 2  # % DESEMPLEO
      t.decimal :median_home_price,          precision: 15, scale: 2  # MEDIAN HOME
      t.decimal :price_per_sqft,             precision: 10, scale: 2  # $ x SQFT
      t.integer :active_listings                                       # LISTADOS ACTIVOS
      t.integer :days_on_market                                        # DAYS ON MARKET
      t.decimal :annual_growth_rate,         precision: 5,  scale: 2  # CRECIMIENTO ANUAL (%)
      t.decimal :annual_budget,              precision: 15, scale: 2  # PRESUPUESTO ANUAL

      # ── Directorio institucional (4 oficinas fijas) ──────────
      t.string :planning_zoning_contact      # PLANNING & ZONING (email)
      t.string :building_division_contact    # BUILDING DIVISION (email)
      t.string :clerk_office_contact         # CLERK OFFICE (email)
      t.string :tax_collector_contact        # TAX COLLECTOR (phone)

      t.timestamps
    end

    add_index :county_market_stats, [:state, :county], unique: true, name: "idx_county_stats_state_county"
    add_index :county_market_stats, :market_status
  end
end
