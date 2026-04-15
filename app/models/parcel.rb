# frozen_string_literal: true

class Parcel < ApplicationRecord
  belongs_to :auction, optional: true
  has_many :parcel_liens, dependent: :destroy
  has_many :reports, dependent: :destroy
  has_many :viewed_parcels, dependent: :destroy

  # ── Mini CRM (Rama 2 escribe, Rama 3 solo lee) ────────────────────
  has_many :parcel_user_tags,  dependent: :destroy
  has_many :parcel_user_notes, dependent: :destroy

  # ── Identidad compuesta (blindaje: UNIQUE INDEX + NOT NULL + validación AR)
  # Alineado con idx_parcels_unique_state_county_pid en PostgreSQL.
  # Triple capa: constraint BD (NOT NULL + UNIQUE) + validación modelo.
  validates :state, :county, :parcel_id, presence: true

  # ── Alias: nombres usados en vistas → columnas reales en BD ─────
  alias_attribute :zip_code,         :zip           # vista usa zip_code, BD tiene zip
  alias_attribute :living_area_sqft, :sqft_living   # vista usa living_area_sqft, BD tiene sqft_living

  # tax_year no existe en BD — exponer como nil seguro hasta que
  # se agregue columna o proveedor externo lo suministre
  def tax_year
    nil # TODO: agregar columna si llega de nuevo proveedor de datos
  end

  # ── Scopes ──────────────────────────────────────────────────────
  scope :for_auction, ->(id) { where(auction_id: id) }
  scope :search_text, ->(q)  {
    where("address ILIKE :q OR parcel_id ILIKE :q OR city ILIKE :q", q: "%#{q}%")
  }
  scope :by_county,    ->(county) { where(county: county) }
  scope :by_state,     ->(state)  { where(state: state) }
  scope :min_bid,      ->(n)      { where("opening_bid >= ?", n) }
  scope :max_bid,      ->(n)      { where("opening_bid <= ?", n) }
  scope :has_coords,              -> { where.not(latitude: nil).where.not(longitude: nil) }

  # ── Calculados al vuelo (NO almacenados) ─────────────────────
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

  # ── Helpers ───────────────────────────────────────────────────
  def full_address
    parts = [address, city, state, zip_code].compact.reject(&:blank?)
    parts.join(", ")
  end

  def has_coords?
    latitude.present? && longitude.present?
  end

  def street_view_url(api_key)
    return nil unless has_coords?
    "https://www.google.com/maps/embed/v1/streetview?key=#{api_key}&location=#{latitude},#{longitude}&fov=90"
  end
end