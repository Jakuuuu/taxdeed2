# frozen_string_literal: true

# Amplía límites de columnas en parcels que eran demasiado estrechos
# para los datos reales del Google Sheet.
#
# Problemas detectados en sync (2026-04-07):
#   - state limit: 2 → Sheet tiene nombres completos ("Florida", "Alabama")
#   - homestead_flag limit: 20 → posibles valores más largos
#   - crime_level limit: 20 → posibles valores más largos
#   - fema_risk_level limit: 100 → posibles valores más largos
#   - zoning limit: 50 → códigos de zoning en algunos counties son más largos
#
class ExpandParcelColumnLimits < ActiveRecord::Migration[7.2]
  def change
    change_column :parcels, :state,            :string, limit: 100
    change_column :parcels, :homestead_flag,   :string, limit: 100
    change_column :parcels, :crime_level,      :string, limit: 50
    change_column :parcels, :fema_risk_level,  :string, limit: 300
    change_column :parcels, :zoning,           :string, limit: 150
    change_column :parcels, :land_use,         :string, limit: 200
    change_column :parcels, :jurisdiction,     :string, limit: 300
  end
end
