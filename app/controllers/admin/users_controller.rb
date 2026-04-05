# frozen_string_literal: true

# Admin::UsersController — lista y detalle de usuarios para soporte y gestión.
#
# Acciones:
#   - index: tabla completa con plan, status, uso
#   - show:  perfil + historial de reportes + acciones de cuenta
#   - reset_usage: resetea créditos consumidos del ciclo (no los del plan)
#   - cancel_subscription: delega a PaymentService, luego actualiza la BD
#
class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [:show, :reset_usage, :cancel_subscription]

  # GET /admin/users
  def index
    # LEFT JOIN reports para evitar N+1 en user.reports.count
    @users = User.includes(:subscription)
                 .left_joins(:reports)
                 .select("users.*, COUNT(reports.id) AS reports_count")
                 .group("users.id")
                 .order(created_at: :desc)
                 .page(params[:page]).per(30)

    @total_users = User.count
    @admin_count = User.where(admin: true).count
  end

  # GET /admin/users/:id
  def show
    @subscription  = @user.subscription
    @reports       = @user.reports.includes(:parcel).order(created_at: :desc).limit(20)
    @stripe_info   = StripeInfoService.fetch(@user)
  end

  # POST /admin/users/:id/reset_usage
  def reset_usage
    sub = @user.subscription
    if sub
      sub.reset_usage!
      redirect_to admin_user_path(@user), notice: "Usage credits reset for #{@user.email}."
    else
      redirect_to admin_user_path(@user), alert: "User has no active subscription."
    end
  end

  # POST /admin/users/:id/cancel_subscription
  # Cancels at period end in Stripe (user keeps access until then),
  # then marks the local record. Delegates Stripe call to PaymentService.
  def cancel_subscription
    sub = @user.subscription
    unless sub
      return redirect_to admin_user_path(@user), alert: "User has no subscription to cancel."
    end

    if sub.canceled?
      return redirect_to admin_user_path(@user), alert: "Subscription is already canceled."
    end

    stripe_ok = PaymentService.cancel_subscription(sub)

    if stripe_ok || PaymentService::MOCK_MODE
      sub.update!(status: "canceled", canceled_at: Time.current)
      redirect_to admin_user_path(@user),
                  notice: "Subscription canceled for #{@user.email}.#{' (Stripe updated)' if stripe_ok}"
    else
      redirect_to admin_user_path(@user),
                  alert: "Could not cancel in Stripe. No changes made — retry or cancel manually in Stripe Dashboard."
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_users_path, alert: "User not found."
  end
end
