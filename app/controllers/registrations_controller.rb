# frozen_string_literal: true

class RegistrationsController < Devise::RegistrationsController
  skip_before_action :authenticate_user!,    only: [:new, :create]
  skip_before_action :set_rls_user_context,  only: [:new, :create]

  def new
    @plan = params[:plan] || "standard"
    super
  end

  def create
    @plan = params[:user][:plan] || "standard"
    build_resource(sign_up_params)

    ActiveRecord::Base.transaction do
      resource.save!

      # ── Establecer contexto RLS dentro de la transacción ─────────────────
      # Durante el registro el usuario aún no tiene sesión activa. Usamos
      # set_config con is_local=FALSE para que el valor persista más allá de
      # la transacción actual (necesario bajo FORCE ROW LEVEL SECURITY en Render).
      # Se limpia / resetea SIEMPRE al finalizar el bloque de registro.
      ActiveRecord::Base.connection.execute(
        "SELECT set_config('app_user.id', '#{resource.id}', false)"
      )

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

    # Limpiar el contexto RLS de la sesión (usamos session-level set_config)
    # El próximo request lo re-establecerá via ApplicationController#set_rls_user_context
    ActiveRecord::Base.connection.execute(
      "SELECT set_config('app_user.id', '0', false)"
    ) rescue nil

    sign_in(resource_name, resource)
    redirect_to research_parcels_path,
      notice: "Welcome to Tax Sale Resources! Your 7-day trial is active."

  rescue ActiveRecord::RecordInvalid => e
    clean_up_resource(resource)
    flash.now[:alert] = e.record.errors.full_messages.join(", ")
    render :new, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[RegistrationsController#create] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    clean_up_resource(resource)
    flash.now[:alert] = "An unexpected error occurred. Please try again."
    render :new, status: :internal_server_error
  end

  private

  def sign_up_params
    params.require(:user).permit(
      :first_name, :last_name, :email, :password, :password_confirmation, :plan
    )
  end

  # Destroy the partially-created user record on transaction failure
  # to avoid ghost accounts with no subscription in the database.
  def clean_up_resource(resource)
    resource.destroy if resource&.persisted?
  rescue StandardError
    # Best-effort cleanup — don't raise twice
  end
end