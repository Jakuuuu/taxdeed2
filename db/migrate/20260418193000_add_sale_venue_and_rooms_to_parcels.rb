# frozen_string_literal: true

# Agrega columnas para Sale Venue, Habitaciones (hab) y Dormitorios (bd)
# a la tabla parcels para importarlas desde el Google Sheet.
class AddSaleVenueAndRoomsToParcels < ActiveRecord::Migration[7.1]
  def change
    add_column :parcels, :sale_venue, :string, comment: "Sale venue from Google Sheet"
    add_column :parcels, :bedrooms,   :integer, comment: "Number of bedrooms (Bd)"
    add_column :parcels, :bathrooms,  :integer, comment: "Number of bathrooms/rooms (Hab)"
  end
end
