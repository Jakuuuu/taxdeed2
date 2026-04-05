# frozen_string_literal: true

class Report < ApplicationRecord
  belongs_to :user
  belongs_to :parcel

  # PDF stored in Active Storage
  has_one_attached :pdf_file

  VALID_TYPES    = %w[avm property_scope title_search].freeze
  VALID_STATUSES = %w[pending ordered generated failed].freeze

  scope :generated,       -> { where(status: "generated") }
  scope :for_parcel,      ->(parcel_id) { where(parcel_id: parcel_id) }
  scope :by_type,         ->(t) { where(report_type: t) }
  scope :latest_first,    -> { order(created_at: :desc) }

  # Named type scopes — usados en admin controllers y dashboard
  scope :title_search,    -> { where(report_type: "title_search") }
  scope :avm,             -> { where(report_type: "avm") }
  scope :property_scope,  -> { where(report_type: "property_scope") }

  def generated? = status == "generated"
  def pending?   = status == "pending"
  def ordered?   = status == "ordered"
  def failed?    = status == "failed"

  def title_search?    = report_type == "title_search"
  def avm?             = report_type == "avm"
  def property_scope?  = report_type == "property_scope"

  def pdf_url
    return nil unless pdf_file.attached?
    Rails.application.routes.url_helpers.rails_blob_url(pdf_file, disposition: "attachment")
  end

  def type_label
    case report_type
    when "avm"            then "AVM Report"
    when "property_scope" then "Property Scope"
    when "title_search"   then "Title Search"
    else report_type.to_s.humanize
    end
  end
end