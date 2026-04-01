# frozen_string_literal: true

class CreateSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true

      # Stripe IDs (mock en M1, reales al activar Stripe)
      t.string :stripe_subscription_id
      t.string :stripe_price_id

      # Plan: standard | pro | premier
      t.string  :plan_name, default: "standard", null: false
      # Status: trial | active | past_due | canceled
      t.string  :status,    default: "trial",    null: false

      # Pricing
      t.integer :trial_amount_cents,  default: 199     # $1.99
      t.integer :annual_amount_cents, default: 49700   # Standard $497

      # Billing period
      t.datetime :current_period_start
      t.datetime :current_period_end
      t.datetime :canceled_at

      # Limites del plan (se populan al crear segun plan_name)
      t.integer :limit_parcels, default: 500,  null: false
      t.integer :limit_avm,     default: 15,   null: false
      t.integer :limit_scope,   default: 2,    null: false
      t.integer :limit_title,   default: 0,    null: false

      # Uso del ciclo anual (se resetea en invoice.payment_succeeded)
      t.integer :used_parcels,  default: 0, null: false
      t.integer :used_avm,      default: 0, null: false
      t.integer :used_scope,    default: 0, null: false

      # Bono de por vida -- NO se resetea en billing
      t.boolean :title_search_used, default: false, null: false

      t.timestamps null: false
    end

    add_index :subscriptions, :stripe_subscription_id, unique: true,
              where: "stripe_subscription_id IS NOT NULL"
  end
end