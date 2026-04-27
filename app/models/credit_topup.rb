# frozen_string_literal: true

# Compras one-time de créditos vía Stripe PaymentIntent.
# NO hace rollover: los créditos comprados se pierden al reset del ciclo.
class CreditTopup < ApplicationRecord
  STATUSES = %w[pending completed failed refunded].freeze

  belongs_to :user

  validates :stripe_payment_intent, presence: true
  validates :credits_purchased, presence: true, numericality: { greater_than: 0 }
  validates :amount_cents,      presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
end
