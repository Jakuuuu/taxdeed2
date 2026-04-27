# frozen_string_literal: true

class AddCreditColumnsToSubscriptions < ActiveRecord::Migration[7.1]
  def change
    change_table :subscriptions, bulk: true do |t|
      t.integer :price_cents
      t.integer :credits_total,  null: false, default: 0
      t.integer :credits_used,   null: false, default: 0
      t.integer :credits_topup,  null: false, default: 0
      t.integer :exports_limit,  null: false, default: 0
      t.integer :exports_used,   null: false, default: 0
    end

    add_index :subscriptions, :status, name: "idx_subscriptions_status"
  end
end
