# frozen_string_literal: true

# Admin::UsersController — lista y detalle de usuarios para soporte y gestión.
#
# Acciones:
#   - index: tabla completa con plan, status, uso (+ search & filters)
#   - show:  perfil + historial de reportes + acciones de cuenta + audit log
#   - reset_usage: resetea créditos consumidos del ciclo (no los del plan)
#   - cancel_subscription: delega a PaymentService, luego actualiza la BD
#   - toggle_admin: promueve member→admin o revoca admin→member
#   - toggle_disable: suspende o reactiva una cuenta de usuario
#
# Todas las acciones mutadoras registran un AdminAuditLog inmutable.
#
class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [:show, :reset_usage, :cancel_subscription, :toggle_admin, :toggle_disable]

  # GET /admin/users
  def index
    scope = User.includes(:subscription)
                .left_joins(:reports)
                .select("users.*, COUNT(reports.id) AS reports_count")
                .group("users.id")

    # ── Search (email or name) ─────────────────────────────────────────
    if params[:q].present?
      term = "%#{params[:q].strip.downcase}%"
      scope = scope.where(
        "LOWER(users.email) LIKE :t OR LOWER(users.first_name) LIKE :t OR LOWER(users.last_name) LIKE :t",
        t: term
      )
    end

    # ── Filter: Plan ───────────────────────────────────────────────────
    if params[:plan].present?
      scope = scope.joins(:subscription).where(subscriptions: { plan_name: params[:plan] })
    end

    # ── Filter: Status ─────────────────────────────────────────────────
    if params[:status].present?
      scope = scope.joins(:subscription).where(subscriptions: { status: params[:status] })
    end

    # ── Filter: Role ───────────────────────────────────────────────────
    case params[:role]
    when "admin"
      scope = scope.where(admin: true)
    when "member"
      scope = scope.where(admin: false)
    end

    @users = scope.order(created_at: :desc)
                  .page(params[:page]).per(30)

    @total_users = User.count
    @admin_count = User.where(admin: true).count

    # Active filter indicator for view
    @active_filters = params.slice(:q, :plan, :status, :role).select { |_, v| v.present? }
  end

  # GET /admin/users/export_csv
  # Exports users as CSV. Respects the same search/filter params as index.
  def export_csv
    require "csv"

    scope = User.includes(:subscription).order(created_at: :desc)

    # ── Reuse same filters as index ────────────────────────────────────
    if params[:q].present?
      term = "%#{params[:q].strip.downcase}%"
      scope = scope.where(
        "LOWER(users.email) LIKE :t OR LOWER(users.first_name) LIKE :t OR LOWER(users.last_name) LIKE :t",
        t: term
      )
    end
    if params[:plan].present?
      scope = scope.joins(:subscription).where(subscriptions: { plan_name: params[:plan] })
    end
    if params[:status].present?
      scope = scope.joins(:subscription).where(subscriptions: { status: params[:status] })
    end
    case params[:role]
    when "admin"  then scope = scope.where(admin: true)
    when "member" then scope = scope.where(admin: false)
    end

    csv_data = CSV.generate(headers: true) do |csv|
      csv << ["ID", "First Name", "Last Name", "Email", "Plan", "Subscription Status",
              "Admin", "Account Status", "Created At"]

      scope.find_each do |user|
        sub = user.subscription
        csv << [
          user.id,
          user.first_name,
          user.last_name,
          user.email,
          sub&.plan_name || "none",
          sub&.status || "none",
          user.admin? ? "Yes" : "No",
          user.disabled? ? "Suspended" : "Active",
          user.created_at.strftime("%Y-%m-%d %H:%M")
        ]
      end
    end

    filename = "taxdeed_users_#{Date.current.strftime('%Y%m%d')}.csv"
    send_data csv_data, filename: filename, type: "text/csv; charset=utf-8", disposition: "attachment"
  end

  # GET /admin/users/:id
  def show
    @subscription  = @user.subscription
    @reports       = @user.reports.includes(:parcel).order(created_at: :desc).limit(20)
    @stripe_info   = StripeInfoService.fetch(@user)
    @audit_logs    = AdminAuditLog.where(target_user: @user)
                                  .includes(:admin_user)
                                  .recent
                                  .limit(15)
  end

  # POST /admin/users/:id/reset_usage
  def reset_usage
    sub = @user.subscription
    if sub
      sub.reset_usage!
      AdminAuditLog.log!(
        admin:   current_user,
        target:  @user,
        action:  "reset_usage",
        details: "Reset usage credits for #{@user.email}."
      )
      redirect_to admin_user_path(@user), notice: "Usage credits reset for #{@user.email}."
    else
      redirect_to admin_user_path(@user), alert: "User has no active subscription."
    end
  end

  # POST /admin/users/:id/cancel_subscription
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
      AdminAuditLog.log!(
        admin:   current_user,
        target:  @user,
        action:  "cancel_subscription",
        details: "Canceled subscription (#{sub.plan_name}) for #{@user.email}.#{' Stripe updated.' if stripe_ok}"
      )
      redirect_to admin_user_path(@user),
                  notice: "Subscription canceled for #{@user.email}.#{' (Stripe updated)' if stripe_ok}"
    else
      redirect_to admin_user_path(@user),
                  alert: "Could not cancel in Stripe. No changes made — retry or cancel manually in Stripe Dashboard."
    end
  end

  # POST /admin/users/:id/toggle_admin
  def toggle_admin
    if @user == current_user
      return redirect_to admin_user_path(@user),
                         alert: "You cannot change your own admin access."
    end

    new_value = !@user.admin
    action    = new_value ? "granted" : "revoked"

    if @user.update(admin: new_value)
      AdminAuditLog.log!(
        admin:   current_user,
        target:  @user,
        action:  "toggle_admin",
        details: "Admin access #{action} for #{@user.email}."
      )
      redirect_to admin_user_path(@user),
                  notice: "Admin access #{action} for #{@user.email}."
    else
      redirect_to admin_user_path(@user),
                  alert: "Could not update admin access."
    end
  end

  # POST /admin/users/:id/toggle_disable
  # Suspends or reactivates a user account.
  # Guard: an admin cannot disable their own account.
  # When disabled, user is immediately signed out via Devise hook.
  def toggle_disable
    if @user == current_user
      return redirect_to admin_user_path(@user),
                         alert: "You cannot disable your own account."
    end

    if @user.disabled?
      # Re-enable
      @user.update!(disabled_at: nil)
      AdminAuditLog.log!(
        admin:   current_user,
        target:  @user,
        action:  "enable_account",
        details: "Re-enabled account for #{@user.email}."
      )
      redirect_to admin_user_path(@user),
                  notice: "Account re-enabled for #{@user.email}."
    else
      # Disable
      @user.update!(disabled_at: Time.current)
      AdminAuditLog.log!(
        admin:   current_user,
        target:  @user,
        action:  "disable_account",
        details: "Suspended account for #{@user.email}. User will be signed out on next request."
      )
      redirect_to admin_user_path(@user),
                  notice: "Account suspended for #{@user.email}. They will be signed out."
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_users_path, alert: "User not found."
  end
end
