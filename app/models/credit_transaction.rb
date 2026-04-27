# frozen_string_literal: true

# Append-only ledger de créditos. Toda operación que altere el balance
# de créditos del usuario crea un registro aquí.
# REGLA: NUNCA UPDATE ni DELETE. Solo INSERT.
class CreditTransaction < ApplicationRecord
  TYPES = %w[unlock topup cycle_reset plan_upgrade individual_purchase].freeze

  belongs_to :user
  belongs_to :parcel, optional: true

  validates :transaction_type, presence: true, inclusion: { in: TYPES }
  validates :credits_delta, presence: true
  validates :credits_balance_after, presence: true

  before_update { raise ActiveRecord::ReadOnlyRecord, "credit_transactions are append-only" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "credit_transactions are append-only" }
end
