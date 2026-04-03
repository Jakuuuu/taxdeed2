# frozen_string_literal: true

class Auction < ApplicationRecord
  has_many :parcels, dependent: :destroy

  STATUSES = %w[upcoming active completed].freeze

  scope :upcoming,   -> { where(status: "upcoming") }
  scope :active,     -> { where(status: "active") }
  scope :completed,  -> { where(status: "completed") }
  scope :visible,    -> { where(status: %w[upcoming active]) }
  scope :by_state,   ->(state) { where(state: state) }
  scope :by_county,  ->(county) { where(county: county) }
  scope :from_date,  ->(date) { where("sale_date >= ?", date) }
  scope :to_date,    ->(date) { where("sale_date <= ?", date) }

  def jurisdiction
    [county, state].compact.join(", ")
  end

  def status_label
    status&.capitalize || "Unknown"
  end

  def upcoming? = status == "upcoming"
  def active?   = status == "active"
  def completed? = status == "completed"
end