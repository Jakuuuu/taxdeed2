# frozen_string_literal: true

class Parcel < ApplicationRecord
  belongs_to :auction, optional: true
  has_many :parcel_liens, dependent: :destroy
  has_many :reports, dependent: :destroy
  has_many :viewed_parcels, dependent: :destroy

  # Campos calculados al vuelo (NO almacenados)
  def adjusted_value_16
    return nil unless opening_bid
    (opening_bid * 1.16).round(2)
  end

  def max_bid_30
    return nil unless assessed_value
    (assessed_value * 0.30).round(2)
  end

  def max_bid_35
    return nil unless assessed_value
    (assessed_value * 0.35).round(2)
  end
end