# frozen_string_literal: true

# Amplía las columnas URL de parcels de varchar(500) a varchar(2048).
#
# Problema detectado en sync (2026-04-22):
#   Al extraer los hyperlinks reales embebidos en las celdas de Google Sheets
#   (en lugar del texto visible "Link"), algunas URLs —especialmente de
#   Google Maps— superan los 500 caracteres originales.
#
class ExpandParcelUrlColumns < ActiveRecord::Migration[7.2]
  def change
    change_column :parcels, :regrid_url,         :string, limit: 2048
    change_column :parcels, :gis_image_url,      :string, limit: 2048
    change_column :parcels, :google_maps_url,    :string, limit: 2048
    change_column :parcels, :fema_url,           :string, limit: 2048
    change_column :parcels, :property_image_url, :string, limit: 2048
    change_column :parcels, :clerk_url,          :string, limit: 2048
    change_column :parcels, :tax_collector_url,  :string, limit: 2048
  end
end
