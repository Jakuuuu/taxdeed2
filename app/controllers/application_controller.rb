# frozen_string_literal: true

class ApplicationController < ActionController::Base
  before_action :authenticate_user!

  # Redirige usuarios autenticados al dashboard, no al root (evita loop con login page)
  def after_sign_in_path_for(resource)
    research_parcels_path
  end

  private

  def require_active_subscription!
    return if current_user.subscription&.active_or_trial?

    # Evitar loop: solo redirigir si no estamos ya en subscription_required
    unless request.path == subscription_required_path
      redirect_to subscription_required_path,
        alert: "Your subscription is inactive. Please renew to continue."
    end
  end

  def require_credits!(type)
    subscription = current_user.subscription
    unless subscription
      redirect_to subscription_required_path, alert: "No active subscription found."
      return
    end

    subscription.with_lock do
      unless subscription.can_use?(type)
        flash[:alert] = "You have reached your #{type.to_s.humanize} limit for this billing period."
        redirect_to research_parcels_path and return
      end
      subscription.increment!("used_#{type}")
    end
  end

  def require_admin!
    redirect_to research_parcels_path, alert: "Unauthorized." unless current_user&.admin?
  end
end