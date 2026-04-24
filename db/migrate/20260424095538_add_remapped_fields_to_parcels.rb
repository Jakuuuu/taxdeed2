# frozen_string_literal: true

# Remapeo Estructural 2026-04-24 — Pipeline Propiedades1
#
# Campos nuevos que se importan del Google Sheet:
#   - price_estimate (pos 72, col BU)  — Estimado de precio del sitio
#   - max_bid_30     (pos 74, col BW)  — Max Bid at 30% (antes computado, ahora importado)
#   - max_bid_35     (pos 75, col BX)  — Max Bid at 35% (antes computado, ahora importado)
#   - technical_analysis (pos 76, col BY) — Análisis técnico (reemplaza comments_do_va en UI)
#   - property_appraiser_url (pos 77, col BZ) — Link Property Appraiser (Resource Center)
#
class AddRemappedFieldsToParcels < ActiveRecord::Migration[7.2]
  def change
    add_column :parcels, :price_estimate, :decimal, precision: 12, scale: 2
    add_column :parcels, :max_bid_30, :decimal, precision: 12, scale: 2
    add_column :parcels, :max_bid_35, :decimal, precision: 12, scale: 2
    add_column :parcels, :technical_analysis, :text
    add_column :parcels, :property_appraiser_url, :string, limit: 500
  end
end
