# frozen_string_literal: true

class CreateCreditTopups < ActiveRecord::Migration[7.1]
  def change
    create_table :credit_topups do |t|
      t.references :user, null: false, foreign_key: true
      t.string     :stripe_payment_intent, limit: 100, null: false
      t.integer    :credits_purchased,                  null: false
      t.integer    :amount_cents,                       null: false
      t.string     :status, limit: 20, null: false, default: "pending"
      t.datetime   :purchased_at

      t.timestamps
    end
  end
end
