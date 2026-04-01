# frozen_string_literal: true

class CreateAuctions < ActiveRecord::Migration[7.2]
  def change
    create_table :auctions do |t|
      t.string  :state,          null: false
      t.string  :county,         null: false
      t.string  :jurisdiction
      # Siempre "tax_deed" en esta version
      t.string  :auction_type,   null: false, default: "tax_deed"
      t.date    :sale_date,      null: false
      t.date    :registration_deadline
      t.date    :bidding_start
      t.integer :parcel_count,   default: 0
      t.decimal :total_amount,   precision: 15, scale: 2
      # upcoming | active | completed
      t.string  :status,         default: "upcoming"
      t.string  :bidding_url,    limit: 500
      t.decimal :latitude,       precision: 10, scale: 8
      t.decimal :longitude,      precision: 11, scale: 8
      t.text    :notes

      t.timestamps null: false
    end

    add_index :auctions, :state
    add_index :auctions, :sale_date
    add_index :auctions, :status
    add_index :auctions, [:county, :state, :sale_date], unique: true,
              name: "idx_auctions_county_state_date"
  end
end