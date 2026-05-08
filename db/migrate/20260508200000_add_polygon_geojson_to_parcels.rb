# frozen_string_literal: true

# Rama 2 — Polygon Hydration: almacenamiento local de GeoJSON para mapa interactivo
#
# Estrategia de "Hidratación Orgánica":
#   Cuando un usuario abre la ficha de una parcela, el sistema extrae el polígono GIS
#   una vez (via Api::LocalGisController → ArcGIS REST) y lo persiste aquí.
#   Rama 2 consume polygon_geojson directamente desde la BD → sin queries on-demand.
#
# Cobertura:
#   Todos los condados de Florida (67) vía FDOR fallback + condados en COUNTY_GIS_REGISTRY.
#   A diferencia de polygon_encoded (Rama 6 / Static Map API), aquí guardamos el
#   GeoJSON crudo (FeatureCollection) para uso con google.maps.Data.addGeoJson().
#
# Columnas:
#   polygon_geojson    — GeoJSON FeatureCollection como text. Puede ser JSON largo (>4KB).
#   polygon_fetched_at — Timestamp del último fetch exitoso. Permite invalidación futura.
#
class AddPolygonGeojsonToParcels < ActiveRecord::Migration[7.2]
  def change
    add_column :parcels, :polygon_geojson, :text
    add_column :parcels, :polygon_fetched_at, :datetime

    # Index parcial: la mayoría de parcelas no tienen GeoJSON aún (pre-hydration).
    # Permite queries eficientes para backfill y admin stats.
    add_index :parcels,
              :polygon_fetched_at,
              where: "polygon_fetched_at IS NOT NULL",
              name:  "index_parcels_on_polygon_fetched_at_not_null"
  end
end
