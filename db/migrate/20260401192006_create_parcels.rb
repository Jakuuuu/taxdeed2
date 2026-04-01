# frozen_string_literal: true

class CreateParcels < ActiveRecord::Migration[7.2]
  def change
    create_table :parcels do |t|
      t.references :auction, foreign_key: true

      # Identificacion
      t.string  :parcel_id,           limit: 50   # col E
      t.string  :address,             limit: 300  # col C
      t.string  :property_address,    limit: 300  # col U
      t.string  :city,                limit: 100
      t.string  :state,               limit: 2    # col B
      t.string  :county,              limit: 100  # col A
      t.string  :zip,                 limit: 10   # col V
      t.decimal :latitude,            precision: 10, scale: 8
      t.decimal :longitude,           precision: 11, scale: 8

      # Propietario (owner_mail_address NO se expone en API publica)
      t.string  :owner_name,          limit: 200  # col S
      t.string  :owner_mail_address,  limit: 300  # col T
      t.text    :legal_description                # col W

      # Financiero
      t.decimal :delinquent_amount,    precision: 12, scale: 2
      t.decimal :opening_bid,          precision: 12, scale: 2  # col D
      t.decimal :assessed_value,       precision: 15, scale: 2  # col K
      t.decimal :land_value,           precision: 15, scale: 2
      t.decimal :improvement_value,    precision: 15, scale: 2
      t.decimal :market_value,         precision: 15, scale: 2  # col J
      t.decimal :estimated_sale_value, precision: 12, scale: 2  # col BM
      t.decimal :price_per_acre,       precision: 12, scale: 2  # calculado: opening_bid / lot_area_acres

      # Caracteristicas fisicas
      t.integer :year_built
      t.decimal :sqft_living,          precision: 10, scale: 2  # col N
      t.decimal :sqft_lot,             precision: 12, scale: 2  # col M
      t.decimal :lot_area_acres,       precision: 10, scale: 4  # col L
      t.string  :minimum_lot_size,     limit: 150               # col O
      t.string  :zoning,               limit: 50                # col P
      t.string  :jurisdiction,         limit: 150               # col Q
      t.string  :land_use,             limit: 100               # col R
      t.string  :property_type,        limit: 50
      t.integer :bedrooms
      t.decimal :bathrooms,            precision: 3,  scale: 1
      t.string  :lot_shape,            limit: 50                # col AF

      # Clasificacion inversion
      t.string  :homestead_flag,       limit: 20      # col Y: Homestead | Investor
      t.string  :crime_level,          limit: 20      # col X: Low | Moderate | High

      # Utilities (yes | no)
      t.string  :electric,             limit: 10      # col AC
      t.string  :water,                limit: 10      # col AD
      t.string  :sewer,                limit: 10      # col AE
      t.string  :hoa,                  limit: 10      # col AM

      # Riesgo ambiental / FEMA
      t.boolean :wetlands                             # col AG
      t.string  :fema_risk_level,      limit: 100     # col AI
      t.text    :fema_notes                           # col AH
      t.string  :fema_url,             limit: 500     # col AJ

      # Links externos (ingresados por equipo humano)
      t.string  :regrid_url,           limit: 500     # col Z
      t.string  :gis_image_url,        limit: 500     # col AA
      t.string  :google_maps_url,      limit: 500     # col AB
      t.string  :property_image_url,   limit: 500     # col AK
      t.string  :clerk_url,            limit: 500     # col BT
      t.string  :tax_collector_url,    limit: 500     # col BU

      # Resultado de subasta
      t.string  :auction_status,       default: "available"  # available | sold | unsold
      t.decimal :winning_bid,          precision: 12, scale: 2

      # Metadata sync
      t.string    :data_source,        default: "google_sheets"
      t.datetime  :last_synced_at

      t.timestamps null: false
    end

    add_index :parcels, :auction_id
    add_index :parcels, [:state, :county], name: "idx_parcels_state_county"
    add_index :parcels, [:latitude, :longitude], name: "idx_parcels_lat_lng"
    add_index :parcels, :parcel_id
    # NO existe tabla parcel_comps -- comparables Zillow son datos internos del equipo
  end
end