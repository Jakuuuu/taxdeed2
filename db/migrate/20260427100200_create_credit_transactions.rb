# frozen_string_literal: true

class CreateCreditTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :credit_transactions do |t|
      t.references :user,   null: false, foreign_key: true
      t.string     :transaction_type,      limit: 30,  null: false
      t.integer    :credits_delta,                     null: false
      t.integer    :credits_balance_after,             null: false
      t.references :parcel, foreign_key: true
      t.string     :stripe_payment_intent, limit: 100
      t.string     :description,           limit: 200

      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :credit_transactions, [:user_id, :created_at], name: "idx_credit_tx_user_created"
    add_index :credit_transactions, :transaction_type,        name: "idx_credit_tx_type"
  end
end
