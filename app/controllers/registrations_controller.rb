# frozen_string_literal: true

class RegistrationsController < Devise::RegistrationsController
  skip_before_action :authenticate_user!, only: [:new, :create]

  def new
    @plan = params[:plan] || "standard"
    super
  end

  def create
    @plan = params[:user][:plan] || "standard"
    build_resource(sign_up_params)

    ActiveRecord::Base.transaction do
      resource.save!

      # 1. Crear Customer (mock o real segun PaymentService::MOCK_MODE)
      customer_id = PaymentService.create_customer(resource)
      resource.update!(stripe_customer_id: customer_id)

      # 2. Crear Subscription en Stripe (mock o real)
      stripe_sub = PaymentService.create_subscription(customer_id, plan: @plan)

      # 3. Calcular limites segun plan elegido
      limits = Subscription::PLAN_LIMITS.fetch(@plan, Subscription::PLAN_LIMITS["standard"])

      # 4. Crear registro Subscription en BD
      resource.create_subscription!(
        stripe_subscription_id: stripe_sub[:id],
        plan_name:              @plan,
        status:                 "trial",
        trial_amount_cents:     199,
        annual_amount_cents:    limits[:annual_cents],
        current_period_start:   Time.current,
        current_period_end:     7.days.from_now,
        limit_parcels:          limits[:parcels],
        limit_avm:              limits[:avm],
        limit_scope:            limits[:scope],
        limit_title:            limits[:title]
      )
    end

    sign_in(resource_name, resource)
    redirect_to research_parcels_path,
      notice: "Welcome to Tax Sale Resources! Your 7-day trial is active."

  rescue ActiveRecord::RecordInvalid => e
    flash[:alert] = e.record.errors.full_messages.join(", ")
    render :new, status: :unprocessable_entity
  end

  private

  def sign_up_params
    params.require(:user).permit(
      :first_name, :last_name, :email, :password, :password_confirmation, :plan
    )
  end
end