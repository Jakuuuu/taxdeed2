# frozen_string_literal: true

# Rama 6 — Clear-to-Bid: extensiones backend
#
# Añade dos columnas a parcels:
#   - polygon_encoded:           Google Encoded Polyline string del polígono de la parcela.
#                                Pre-computed por EncodeParcelPolygonJob desde el ArcGIS REST
#                                del condado (vía Api::LocalGisController::COUNTY_GIS_REGISTRY).
#                                Solo disponible para condados registrados (~6 de FL en 2026-05).
#                                Para los demás → nil → helper cae a marker fallback.
#
#   - clear_to_bid_grade_locked: si true, el sync NO sobrescribe el grade override admin
#                                aunque la celda F del Sheet traiga valor distinto.
#                                Política de "Lock against Sheet sync" (admin form).
class AddPolygonEncodedAndLockToParcels < ActiveRecord::Migration[7.2]
  def change
    add_column :parcels, :polygon_encoded, :text
    add_column :parcels, :clear_to_bid_grade_locked, :boolean, null: false, default: false

    # Index parcial: la mayoría de parcels no tendrán polygon_encoded (condados fuera del registry).
    add_index :parcels,
              :polygon_encoded,
              where: "polygon_encoded IS NOT NULL",
              name:  "index_parcels_on_polygon_encoded_not_null"
  end
end
