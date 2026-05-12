# frozen_string_literal: true

module Research
  class SettingsController < BaseController
    def show
      @user         = current_user
      @subscription = current_user.subscription
      @active_tab   = params[:tab] || "profile"
    end

    def profile
      @user = current_user
      if @user.update(profile_params)
        redirect_to research_settings_path(tab: "profile"),
          notice: "Profile updated successfully."
      else
        @subscription = current_user.subscription
        @active_tab   = "profile"
        render :show, status: :unprocessable_entity
      end
    end

    # PATCH /research/settings/notifications
    # Default lead time aplicado a watches NUEVOS (no retroactivo).
    # Email global queda persistido aunque la entrega real sea Fase 2.
    def notifications
      days = params[:default_notify_days_before].to_i
      days = 7 unless ParcelWatch::ALLOWED_DAYS.include?(days)
      current_user.update!(
        default_notify_days_before:  days,
        email_notifications_enabled: ActiveModel::Type::Boolean.new.cast(params[:email_notifications_enabled])
      )
      redirect_to research_settings_path(tab: "notifications"),
        notice: "Preferencias de notificación guardadas."
    end

    def cancel_subscription
      subscription = current_user.subscription
      if subscription.nil? || subscription.status == "canceled"
        redirect_to research_settings_path(tab: "subscription"),
          alert: "Subscription is not active."
        return
      end

      result = PaymentService.cancel_subscription(subscription)

      if result[:success]
        redirect_to research_settings_path(tab: "subscription"),
          notice: "Your subscription will be canceled at the end of your current billing period. You will retain access until then."
      else
        redirect_to research_settings_path(tab: "subscription"),
          alert: "Could not cancel subscription: #{result[:error]}"
      end
    end

    private

    def profile_params
      params.require(:user).permit(:first_name, :last_name, :email, :phone, :locale)
    end
  end
end
