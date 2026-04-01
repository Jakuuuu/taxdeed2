# frozen_string_literal: true

module Stripe
  class WebhooksController < ApplicationController
    skip_before_action :authenticate_user!
    skip_before_action :verify_authenticity_token

    def create
      payload    = request.body.read
      sig_header = request.env["HTTP_STRIPE_SIGNATURE"]

      if PaymentService::MOCK_MODE
        # En modo mock simplemente acepta el payload sin verificar firma
        Rails.logger.info "[Stripe Webhook MOCK] event received"
        render json: { received: true } and return
      end

      begin
        event = ::Stripe::Webhook.construct_event(
          payload,
          sig_header,
          Rails.application.credentials.stripe[:webhook_secret]
        )
      rescue ::Stripe::SignatureVerificationError => e
        render json: { error: e.message }, status: :bad_request and return
      end

      handle_event(event)
      render json: { received: true }
    end

    private

    def handle_event(event)
      case event.type
      when "invoice.payment_succeeded"
        # Renovacion anual exitosa — resetear contadores de uso
        sub_id = event.data.object.subscription
        subscription = ::Subscription.find_by(stripe_subscription_id: sub_id)
        subscription&.update!(
          status:          "active",
          used_parcels:    0,
          used_avm:        0,
          used_scope:      0,
          current_period_start: Time.current,
          current_period_end:   1.year.from_now
        )
      when "customer.subscription.deleted"
        sub_id = event.data.object.id
        ::Subscription.find_by(stripe_subscription_id: sub_id)&.update!(status: "canceled")
      end
    end
  end
end