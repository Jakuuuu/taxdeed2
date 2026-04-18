# frozen_string_literal: true

# Agrega columnas para Sale Venue, Habitaciones (hab) y Dormitorios (bd)
# a la tabla parcels para importarlas desde el Google Sheet.
# Usa column_exists? para evitar DuplicateColumn si alguna ya existe.
class AddSaleVenueAndRoomsToParcels < ActiveRecord::Migration[7.1]
  def change
    add_column :parcels, :sale_venue, :string, comment: "Sale venue from Google Sheet" unless column_exists?(:parcels, :sale_venue)
    add_column :parcels, :bedrooms,   :integer, comment: "Number of bedrooms (Bd)"     unless column_exists?(:parcels, :bedrooms)
    add_column :parcels, :bathrooms,  :integer, comment: "Number of bathrooms (Hab)"   unless column_exists?(:parcels, :bathrooms)
  end
end
