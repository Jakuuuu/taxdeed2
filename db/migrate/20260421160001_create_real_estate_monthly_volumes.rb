# frozen_string_literal: true

# Migración: real_estate_monthly_volumes — Serie temporal del median sale price
#
# Fuente: Pestaña "Mercados" del Google Sheet
# Estructura del Sheet: TABLA CRUZADA HORIZONTAL
#   Fila 3 (headers): Estado | Condados | Enero de 2012 | Febrero de 2012 | ... | Febrero de 2026
#   Fila 4+:           Florida | Alachua  | $164,950.00  | $196,256.00     | ...
#
# Cada celda = median sale price de ese condado en ese mes.
# El pipeline transpone cada fila en ~170 registros verticales.
#
class CreateRealEstateMonthlyVolumes < ActiveRecord::Migration[7.2]
  def change
    create_table :real_estate_monthly_volumes do |t|
      t.references :county_market_stat, null: false, foreign_key: true

      t.date    :period_date,    null: false   # Primer día del mes (e.g., 2024-01-01)
      t.decimal :volume_amount,  null: false, precision: 15, scale: 2  # Median sale price

      t.timestamps
    end

    add_index :real_estate_monthly_volumes,
              [:county_market_stat_id, :period_date],
              unique: true,
              name: "idx_volumes_county_period"
  end
end
