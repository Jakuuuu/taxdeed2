# frozen_string_literal: true

class Report < ApplicationRecord
  belongs_to :user
  belongs_to :parcel

  VALID_TYPES = %w[avm property_scope title_search].freeze
  VALID_STATUSES = %w[pending ordered generated failed].freeze

  scope :generated,      -> { where(status: "generated") }
  scope :for_parcel,     ->(parcel_id) { where(parcel_id: parcel_id) }
  scope :by_type,        ->(t) { where(report_type: t) }
  scope :latest_first,   -> { order(created_at: :desc) }

  def generated? = status == "generated"
  def pending?   = status == "pending"
  def ordered?   = status == "ordered"
  def failed?    = status == "failed"

  def type_label
    case report_type
    when "avm"           then "AVM Report"
    when "property_scope" then "Property Scope"
    when "title_search"  then "Title Search"
    else report_type.to_s.humanize
    end
  end
end