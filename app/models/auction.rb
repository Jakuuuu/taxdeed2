# frozen_string_literal: true

class Auction < ApplicationRecord
  has_many :parcels, dependent: :destroy

  scope :upcoming,  -> { where(status: "upcoming") }
  scope :active,    -> { where(status: "active") }
  scope :completed, -> { where(status: "completed") }
  scope :by_state,  ->(state) { where(state: state) }
end