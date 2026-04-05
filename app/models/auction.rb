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
  scope :by_state,   ->(state)  { where(state: state) }
  scope :by_county,  ->(county) { where(county: county) }
  scope :from_date,  ->(date)   { where("sale_date >= ?", date) }
  scope :to_date,    ->(date)   { where("sale_date <= ?", date) }
  # For map: only auctions with valid coordinates
  scope :for_map,    -> { visible.where.not(latitude: nil).where.not(longitude: nil) }

  # ── Validations ─────────────────────────────────────────────────────────────
  validates :state, :county, :sale_date, presence: true
  validates :auction_type, inclusion: { in: ["tax_deed"] }
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  # ── Derived Attributes ──────────────────────────────────────────────────────
  def jurisdiction
    [county, state].compact.join(", ")
  end

  def status_label
    status&.capitalize || "Unknown"
  end

  def upcoming?   = status == "upcoming"
  def active?     = status == "active"
  def completed?  = status == "completed"

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