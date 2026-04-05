# frozen_string_literal: true

# Admin::DashboardController — overview stats for the internal operations panel
class Admin::DashboardController < Admin::BaseController
  def index
    # Title Search stats
    @pending_title_searches = Report.title_search.where(status: :ordered).count
    @generated_this_month   = Report.title_search.where(status: :generated)
                                    .where(updated_at: 1.month.ago..).count

    # Auctions
    @active_auctions   = Auction.active.count
    @upcoming_auctions = Auction.upcoming.count

    # Users
    @total_users = User.count
    @admin_count = User.where(admin: true).count
    @users_by_plan = Subscription.joins(:user)
                                 .group(:plan_name)
                                 .count

    # Recent title searches (5 most recent pending)
    @recent_pending = Report.title_search
                            .where(status: :ordered)
                            .includes(:user, :parcel)
                            .order(created_at: :asc)
                            .limit(5)

    # Last sync
    @last_sync = SyncLog.order(started_at: :desc).first
  end
end
