# frozen_string_literal: true

# ==============================================================================
# Test: AuctionTodayPipelineAlertsJob
#
# Cubre:
#   1. Crea Notification(kind: 'auction_today') para cada PipelineProperty
#      cuya parcel.auction.sale_date == today.
#   2. Idempotencia: ejecutar dos veces el mismo día NO duplica.
#   3. payload.report_cta resuelve correctamente:
#        - 'download' cuando hay Report(title_search, generated)
#        - 'generate' cuando ficha desbloqueada sin reporte generated
#        - nil       cuando ficha bloqueada
#   4. NO crea notificación para parcelas con sale_date != today.
#   5. Funciona aunque el usuario NO tenga ParcelWatch (premisa central
#      de este job vs UpcomingAuctionAlertsJob).
#
# Ejecutar con:
#   bundle exec rails test test/jobs/auction_today_pipeline_alerts_job_test.rb
# ==============================================================================

require "test_helper"

class AuctionTodayPipelineAlertsJobTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "today-#{SecureRandom.hex(4)}@example.com", password: "password123456")
    PipelineStage.seed_for!(@user)
    @target_stage = @user.pipeline_stages.find_by!(name: "Target")
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  def make_parcel(sale_date:, county: "Hillsborough", state: "FL")
    parcel = Parcel.create!(
      state:     state,
      county:    county,
      parcel_id: "TEST-#{SecureRandom.hex(4)}",
      address:   "100 Main St"
    )
    auction = Auction.find_or_create_by!(
      state: state, county: county, sale_date: sale_date
    ) { |a| a.auction_type = "tax_deed"; a.status = "upcoming" }
    parcel.update!(auction_id: auction.id)
    parcel
  end

  def add_to_pipeline(parcel)
    PipelineProperty.create!(
      user: @user, parcel: parcel,
      pipeline_stage: @target_stage, position: 0
    )
  end

  # ── Tests ──────────────────────────────────────────────────────────────

  test "creates auction_today notification for parcel whose sale_date is today" do
    parcel = make_parcel(sale_date: Date.current)
    add_to_pipeline(parcel)

    assert_difference -> { @user.notifications.where(kind: "auction_today").count }, 1 do
      AuctionTodayPipelineAlertsJob.new.perform
    end

    n = @user.notifications.where(kind: "auction_today").last
    assert_equal "Parcel", n.notifiable_type
    assert_equal parcel.id, n.notifiable_id
    assert_equal "in_app", n.delivery_channel
    assert_equal Date.current.iso8601, n.payload["sale_date"]
    assert_equal (Date.current + 7.days).iso8601, n.payload["auto_archive_at"]
  end

  test "does NOT notify for parcels with sale_date in the future" do
    parcel = make_parcel(sale_date: Date.current + 5.days)
    add_to_pipeline(parcel)

    assert_no_difference -> { @user.notifications.count } do
      AuctionTodayPipelineAlertsJob.new.perform
    end
  end

  test "does NOT notify for parcels with sale_date in the past" do
    parcel = make_parcel(sale_date: Date.current - 1.day)
    add_to_pipeline(parcel)

    assert_no_difference -> { @user.notifications.count } do
      AuctionTodayPipelineAlertsJob.new.perform
    end
  end

  test "is idempotent — running twice the same day does not duplicate" do
    parcel = make_parcel(sale_date: Date.current)
    add_to_pipeline(parcel)

    AuctionTodayPipelineAlertsJob.new.perform
    assert_no_difference -> { @user.notifications.where(kind: "auction_today").count } do
      AuctionTodayPipelineAlertsJob.new.perform
    end
  end

  test "works without ParcelWatch — premisa: estar en pipeline basta" do
    parcel = make_parcel(sale_date: Date.current)
    add_to_pipeline(parcel)
    assert_equal 0, @user.parcel_watches.count, "precondición: usuario sin watch"

    AuctionTodayPipelineAlertsJob.new.perform

    assert_equal 1, @user.notifications.where(kind: "auction_today").count
  end

  test "report_cta = 'download' when a generated title_search Report exists" do
    parcel = make_parcel(sale_date: Date.current)
    add_to_pipeline(parcel)
    Report.create!(
      user: @user, parcel: parcel,
      report_type: "title_search", status: "generated", payment_status: "paid"
    )

    AuctionTodayPipelineAlertsJob.new.perform
    n = @user.notifications.where(kind: "auction_today").last
    assert_equal "download", n.payload["report_cta"]
  end

  test "report_cta = 'generate' when ficha unlocked but no generated report" do
    parcel = make_parcel(sale_date: Date.current)
    add_to_pipeline(parcel)
    ViewedParcel.create!(user: @user, parcel: parcel, unlocked: true)

    AuctionTodayPipelineAlertsJob.new.perform
    n = @user.notifications.where(kind: "auction_today").last
    assert_equal "generate", n.payload["report_cta"]
  end

  test "report_cta = nil when ficha is locked (no empuja al paywall el día D)" do
    parcel = make_parcel(sale_date: Date.current)
    add_to_pipeline(parcel)
    # No ViewedParcel.unlocked, no Report

    AuctionTodayPipelineAlertsJob.new.perform
    n = @user.notifications.where(kind: "auction_today").last
    assert_nil n.payload["report_cta"]
  end

  test "report_cta = 'download' takes precedence over unlocked-without-report" do
    parcel = make_parcel(sale_date: Date.current)
    add_to_pipeline(parcel)
    ViewedParcel.create!(user: @user, parcel: parcel, unlocked: true)
    Report.create!(
      user: @user, parcel: parcel,
      report_type: "title_search", status: "generated", payment_status: "paid"
    )

    AuctionTodayPipelineAlertsJob.new.perform
    n = @user.notifications.where(kind: "auction_today").last
    assert_equal "download", n.payload["report_cta"]
  end

  test "non-generated reports do not trigger 'download' CTA" do
    parcel = make_parcel(sale_date: Date.current)
    add_to_pipeline(parcel)
    ViewedParcel.create!(user: @user, parcel: parcel, unlocked: true)
    Report.create!(
      user: @user, parcel: parcel,
      report_type: "title_search", status: "pending", payment_status: "paid"
    )

    AuctionTodayPipelineAlertsJob.new.perform
    n = @user.notifications.where(kind: "auction_today").last
    assert_equal "generate", n.payload["report_cta"], "pending report no cuenta como descargable"
  end

  test "creates one notification per pipeline_property even across multiple users" do
    other_user = User.create!(email: "other-#{SecureRandom.hex(4)}@example.com", password: "password123456")
    PipelineStage.seed_for!(other_user)
    other_target = other_user.pipeline_stages.find_by!(name: "Target")

    parcel = make_parcel(sale_date: Date.current)
    add_to_pipeline(parcel)
    PipelineProperty.create!(
      user: other_user, parcel: parcel,
      pipeline_stage: other_target, position: 0
    )

    AuctionTodayPipelineAlertsJob.new.perform

    assert_equal 1, @user.notifications.where(kind: "auction_today").count
    assert_equal 1, other_user.notifications.where(kind: "auction_today").count
  end
end
