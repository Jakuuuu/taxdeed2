# frozen_string_literal: true

# Fase 1 — Alinear tabla reports con el modelo de monetización documentado.
# Title Search Reports se cobran vía Stripe PaymentIntent (pago directo USD),
# NO consumen créditos de suscripción.
#
# Columnas añadidas:
#   stripe_payment_intent — ID del PaymentIntent de Stripe
#   amount_cents          — Monto cobrado en centavos USD
#   payment_status        — unpaid | paid | refunded
#   provider_ref          — Referencia del proveedor externo (e.g. DataTrace)
#   download_url          — URL pública alternativa del PDF
#   ordered_at            — Timestamp de confirmación de pago
#   generated_at          — Timestamp de fulfillment completado
#
# NOTA: ordered_at y generated_at ya existían en el schema original.
#       Se usa unless column_exists? para hacerla idempotente.
#
class AddPaymentFieldsToReports < ActiveRecord::Migration[7.2]
  def change
    add_column :reports, :stripe_payment_intent, :string  unless column_exists?(:reports, :stripe_payment_intent)
    add_column :reports, :amount_cents,          :integer unless column_exists?(:reports, :amount_cents)
    add_column :reports, :payment_status,        :string, default: "unpaid" unless column_exists?(:reports, :payment_status)
    add_column :reports, :provider_ref,          :string  unless column_exists?(:reports, :provider_ref)
    add_column :reports, :download_url,          :string  unless column_exists?(:reports, :download_url)
    add_column :reports, :ordered_at,            :datetime unless column_exists?(:reports, :ordered_at)
    add_column :reports, :generated_at,          :datetime unless column_exists?(:reports, :generated_at)

    unless index_exists?(:reports, :stripe_payment_intent, name: "idx_reports_stripe_pi")
      add_index :reports, :stripe_payment_intent, unique: true,
                where: "stripe_payment_intent IS NOT NULL",
                name: "idx_reports_stripe_pi"
    end

    unless index_exists?(:reports, :payment_status, name: "idx_reports_payment_status")
      add_index :reports, :payment_status, name: "idx_reports_payment_status"
    end
  end
end
