# frozen_string_literal: true

class Report < ApplicationRecord
  belongs_to :user
  belongs_to :parcel

  # PDF stored in Active Storage
  has_one_attached :pdf_file

  VALID_TYPES      = %w[avm property_scope title_search].freeze
  VALID_STATUSES   = %w[pending ordered generated failed].freeze
  PAYMENT_STATUSES = %w[unpaid paid refunded].freeze

  scope :generated,       -> { where(status: "generated") }
  scope :for_parcel,      ->(parcel_id) { where(parcel_id: parcel_id) }
  scope :by_type,         ->(t) { where(report_type: t) }
  scope :latest_first,    -> { order(created_at: :desc) }

  # Named type scopes — usados en admin controllers y dashboard
  scope :title_search,    -> { where(report_type: "title_search") }
  scope :avm,             -> { where(report_type: "avm") }
  scope :property_scope,  -> { where(report_type: "property_scope") }

  # Payment scopes — Rama 3 monetización directa vía Stripe
  scope :paid,            -> { where(payment_status: "paid") }
  scope :unpaid,          -> { where(payment_status: "unpaid") }

  def generated? = status == "generated"
  def pending?   = status == "pending"
  def ordered?   = status == "ordered"
  def failed?    = status == "failed"

  def title_search?    = report_type == "title_search"
  def avm?             = report_type == "avm"
  def property_scope?  = report_type == "property_scope"

  # ── Payment helpers ──────────────────────────────────────────────
  def paid?      = payment_status == "paid"
  def unpaid?    = payment_status == "unpaid"
  def refunded?  = payment_status == "refunded"

  def amount_dollars
    return nil unless amount_cents
    amount_cents / 100.0
  end

  def stripe_dashboard_url
    return nil if stripe_payment_intent.blank?
    "https://dashboard.stripe.com/payments/#{stripe_payment_intent}"
  end

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