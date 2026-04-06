# frozen_string_literal: true

class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :set_rls_user_context

  # Redirige usuarios autenticados al dashboard, no al root
  def after_sign_in_path_for(resource)
    research_parcels_path
  end

  private

  # ── Row Level Security context ────────────────────────────────────────────
  # Establece el user_id de la sesión actual como variable de configuración de
  # PostgreSQL. La migración 20260406154000 crea políticas que leen este valor
  # para filtrar filas automáticamente en el motor de BD.
  #
  # '0' = sentinel para admin/Sidekiq (bypasa el filtro — ver migración).
  # El SET es LOCAL: se limita a la transacción actual, sin riesgo de leak
  # entre requests en un pool de conexiones.
  def set_rls_user_context
    return unless current_user

    ActiveRecord::Base.connection.execute(
      "SELECT set_config('app_user.id', '#{current_user.id}', true)"
    )
  rescue ActiveRecord::StatementInvalid
    # Si RLS aún no está migrado (dev fresh), no romper la app
    nil
  end

  def require_active_subscription!
    return if current_user.subscription&.active_or_trial?

    # Evitar loop: solo redirigir si no estamos ya en subscription_required
    unless request.path == subscription_required_path
      redirect_to subscription_required_path,
        alert: "Your subscription is inactive. Please renew to continue."
    end
  end

  # NOTE: require_admin! vive en Admin::BaseController (no duplicar aquí).
  # require_credits! removido — se llama directamente en PurchasedReportsController.
end