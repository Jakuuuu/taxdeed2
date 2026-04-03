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

    def cancel_subscription
      subscription = current_user.subscription
      if subscription.nil? || subscription.status == "canceled"
        redirect_to research_settings_path(tab: "subscription"),
          alert: "Subscription is not active."
        return
      end

      begin
        Stripe::Subscription.cancel(subscription.stripe_subscription_id)
        # Webhook `customer.subscription.deleted` will update DB status
        redirect_to research_settings_path(tab: "subscription"),
          notice: "Your subscription has been canceled. You will retain access until the end of your current billing period."
      rescue Stripe::StripeError => e
        redirect_to research_settings_path(tab: "subscription"),
          alert: "Could not cancel subscription: #{e.message}"
      end
    end

    private

    def profile_params
      params.require(:user).permit(:first_name, :last_name, :email, :phone)
    end
  end
end
