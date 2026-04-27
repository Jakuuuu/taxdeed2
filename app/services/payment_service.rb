# frozen_string_literal: true

# PaymentService — Capa de abstraccion de pagos
#
# MODO SIMULACION (MOCK_MODE = true):
#   Genera IDs ficticios y simula el flujo completo de Stripe.
#   La tabla subscriptions queda correctamente poblada para
#   pruebas reales del resto del sistema.
#
# PARA ACTIVAR STRIPE REAL:
#   1. Configurar credenciales en credentials.yml.enc
#   2. Cambiar MOCK_MODE = false
#   3. Activar webhook endpoint /stripe/webhooks en Stripe Dashboard
#   4. Ver TODO en el plan para el checklist completo (Modulo 6)
#
class PaymentService
  MOCK_MODE = ENV.fetch("STRIPE_MOCK_MODE", Rails.env.production? ? "false" : "true") == "true"

  # Crea un Customer en Stripe y retorna su ID
  def self.create_customer(user)
    if MOCK_MODE
      "cus_MOCK_#{SecureRandom.hex(8)}"
    else
      Stripe::Customer.create(
        email: user.email,
        name:  user.full_name,
        metadata: { user_id: user.id }
      ).id
    end
  end

  # Adjunta un PaymentMethod a un Customer
  def self.attach_payment_method(customer_id, payment_method_id)
    return true if MOCK_MODE

    Stripe::PaymentMethod.attach(
      payment_method_id,
      { customer: customer_id }
    )
    Stripe::Customer.update(customer_id, {
      invoice_settings: { default_payment_method: payment_method_id }
    })
    true
  end

  # Crea una Subscription con trial de 7 dias -> precio anual del plan
  # Retorna hash con :id y :status
  def self.create_subscription(customer_id, plan:)
    if MOCK_MODE
      { id: "sub_MOCK_#{SecureRandom.hex(8)}", status: "trialing" }
    else
      price_id = Rails.application.credentials.dig(:stripe, :"price_#{plan}")
      sub = Stripe::Subscription.create(
        customer:          customer_id,
        items:             [{ price: price_id }],
        trial_period_days: 7,
        payment_settings:  { save_default_payment_method: "on_subscription" },
        expand:            ["latest_invoice.payment_intent"]
      )
      { id: sub.id, status: sub.status }
    end
  end

  # Cancela una suscripción al final del período actual (cancel_at_period_end).
  # Retorna: { success: true } o { success: false, error: "mensaje" }
  #
  # En MOCK_MODE: simula cancel exitoso.
  # Si stripe_subscription_id está en blanco: error inmediato.
  def self.cancel_subscription(sub)
    if sub.stripe_subscription_id.blank?
      return { success: false, error: "No Stripe subscription ID found." }
    end

    if MOCK_MODE
      return { success: true }
    end

    Stripe::Subscription.update(sub.stripe_subscription_id, { cancel_at_period_end: true })
    { success: true }
  rescue Stripe::StripeError => e
    Rails.logger.error("[PaymentService] Stripe cancel failed for sub #{sub.id}: #{e.message}")
    { success: false, error: e.message }
  end
end