# frozen_string_literal: true

# StripeInfoService — Lectura de datos de Stripe para el Admin Panel (solo lectura)
#
# Diseño:
#   - Funciona en MOCK_MODE igual que PaymentService (IDs ficticios = no llama a Stripe)
#   - En producción real, hace 1-2 llamadas de API con rescue para no romper el admin
#     si Stripe está down o el ID es inválido.
#   - Retorna un hash con los datos necesarios, o nil si no aplica.
#
# Uso:
#   info = StripeInfoService.fetch(user)
#   info[:customer_url]      # => "https://dashboard.stripe.com/customers/cus_ABC"
#   info[:subscription_url]  # => "https://dashboard.stripe.com/subscriptions/sub_XYZ"
#   info[:latest_invoice]    # => { amount: "$497.00", date: "03/15/2026", status: "paid" }
#   info[:mock]              # => true/false
#
class StripeInfoService
  DASHBOARD_BASE = "https://dashboard.stripe.com".freeze

  # @param user [User]  must have stripe_customer_id
  # @return [Hash, nil]  nil if no stripe data available
  def self.fetch(user)
    sub = user.subscription
    return nil unless user.stripe_customer_id.present? || sub&.stripe_subscription_id.present?

    # Detect mock IDs — do not call Stripe API for mocks
    is_mock = user.stripe_customer_id&.start_with?("cus_MOCK") ||
              sub&.stripe_subscription_id&.start_with?("sub_MOCK")

    if is_mock || PaymentService::MOCK_MODE
      build_mock_result(user, sub)
    else
      build_live_result(user, sub)
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  def self.build_mock_result(user, sub)
    {
      mock:                 true,
      customer_id:          user.stripe_customer_id,
      customer_url:         nil,
      subscription_id:      sub&.stripe_subscription_id,
      subscription_url:     nil,
      price_id:             sub&.stripe_price_id,
      latest_invoice:       nil,
      payment_method_brand: nil,
      payment_method_last4: nil
    }
  end

  def self.build_live_result(user, sub)
    result = {
      mock:             false,
      customer_id:      user.stripe_customer_id,
      customer_url:     stripe_url("customers", user.stripe_customer_id),
      subscription_id:  sub&.stripe_subscription_id,
      subscription_url: stripe_url("subscriptions", sub&.stripe_subscription_id),
      price_id:         sub&.stripe_price_id,
      latest_invoice:       nil,
      payment_method_brand: nil,
      payment_method_last4: nil
    }

    # Fetch subscription details (latest invoice + payment method)
    if sub&.stripe_subscription_id.present?
      stripe_sub = Stripe::Subscription.retrieve(
        id:     sub.stripe_subscription_id,
        expand: ["latest_invoice", "default_payment_method"]
      )

      # Latest invoice
      inv = stripe_sub.latest_invoice
      if inv && inv.respond_to?(:amount_paid)
        result[:latest_invoice] = {
          amount:     format_cents(inv.amount_paid),
          date:       Time.at(inv.created).strftime("%m/%d/%Y"),
          status:     inv.status,
          invoice_url: inv.hosted_invoice_url
        }
      end

      # Payment method
      pm = stripe_sub.default_payment_method
      if pm&.card
        result[:payment_method_brand] = pm.card.brand&.capitalize
        result[:payment_method_last4] = pm.card.last4
      end
    end

    result
  rescue Stripe::StripeError => e
    Rails.logger.warn("[StripeInfoService] API error for user #{user.id}: #{e.message}")
    # Return partial result without crashing the admin panel
    {
      mock:            false,
      error:           e.message,
      customer_id:     user.stripe_customer_id,
      customer_url:    stripe_url("customers", user.stripe_customer_id),
      subscription_id: sub&.stripe_subscription_id,
      subscription_url: stripe_url("subscriptions", sub&.stripe_subscription_id)
    }
  end

  def self.stripe_url(resource, id)
    return nil if id.blank?
    "#{DASHBOARD_BASE}/#{resource}/#{id}"
  end

  def self.format_cents(cents)
    return "—" unless cents
    "$#{format('%.2f', cents / 100.0)}"
  end

  private_class_method :build_mock_result, :build_live_result, :stripe_url, :format_cents
end
