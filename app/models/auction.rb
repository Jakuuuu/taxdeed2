# frozen_string_literal: true

class Auction < ApplicationRecord
  has_many :parcels, dependent: :destroy

  STATUSES = %w[upcoming active completed].freeze

  # ── Scopes ──────────────────────────────────────────────────────────────────
  scope :upcoming,   -> { where(status: "upcoming") }
  scope :active,     -> { where(status: "active") }
  scope :completed,  -> { where(status: "completed") }
  # Default scope for index / map — excludes completed
  scope :visible,    -> { where(status: %w[upcoming active]) }
  scope :by_state,   ->(state)  { where("LOWER(state) = ?", state.to_s.downcase) }
  scope :by_county,  ->(county) { where("LOWER(county) = ?", county.to_s.downcase) }
  scope :from_date,  ->(date)   { where("sale_date >= ?", date) }
  scope :to_date,    ->(date)   { where("sale_date <= ?", date) }
  # For map: only auctions with valid coordinates
  scope :for_map,    -> { visible.where.not(latitude: nil).where.not(longitude: nil) }

  # ── Time-based dynamic scopes (Motor de Tiempo) ────────────────────────────
  # Subastas con sale_date >= hoy → activas temporalmente
  scope :time_active, -> { where("sale_date >= ?", Date.current) }
  # Subastas con sale_date < hoy → pasadas (Prior Sale Results)
  scope :time_past,   -> { where("sale_date < ?", Date.current) }
  # Combinado: visible + activas en el tiempo (para uso en UI principal)
  scope :active_visible, -> { visible.time_active }
  # Combinado: prior results (sin importar status, pero con sale_date pasada)
  scope :past_visible,   -> { where("sale_date < ?", Date.current) }

  # ── Validations ─────────────────────────────────────────────────────────────
  validates :state, :county, :sale_date, presence: true
  validates :auction_type, inclusion: { in: ["tax_deed"] }
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  # ── Derived Attributes ──────────────────────────────────────────────────────
  def jurisdiction
    [county, state].compact.join(", ")
  end

  # Usado en el picker modal de parcelas
  def parcel_count
    read_attribute(:parcel_count) || parcels.count
  end

  def status_label
    status&.capitalize || "Unknown"
  end

  def upcoming?   = status == "upcoming"
  def active?     = status == "active"
  def completed?  = status == "completed"

  # Dynamic temporal classification
  def time_active?
    sale_date.present? && sale_date >= Date.current
  end

  def time_past?
    sale_date.present? && sale_date < Date.current
  end

  # Days until sale date (nil if past or unknown)
  def days_until_sale
    return nil unless sale_date
    diff = (sale_date - Date.today).to_i
    diff >= 0 ? diff : nil
  end

  # Formatted total amount string
  def formatted_amount
    return nil unless total_amount&.positive?
    "$#{ActiveSupport::NumberHelper.number_to_delimited(total_amount.to_i)}"
  end

  # Summary of key dates for the timeline
  def date_range_label
    parts = []
    parts << "Reg. Deadline: #{registration_deadline.strftime('%b %d')}" if registration_deadline
    parts << "Bidding: #{bidding_start.strftime('%b %d')}" if bidding_start
    parts << "Sale: #{sale_date.strftime('%b %d, %Y')}" if sale_date
    parts.join(" → ")
  end
end