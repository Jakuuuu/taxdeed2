# frozen_string_literal: true

# ==============================================================================
# Test: ArchivePostAuctionPipelineJob
#
# Cubre:
#   1. Mueve a 'Archived' las cards cuya sale_date pasó hace > 7 días.
#   2. NO toca cards con sale_date reciente (≤ 7 días post o futura).
#   3. Respeta cards en stage system_key='won' (NO las archiva).
#   4. Respeta cards ya en stage system_key='archived' (NO las re-mueve).
#   5. Skip silencioso si el usuario no tiene stage system_key='archived'.
#
# Ejecutar con:
#   bundle exec rails test test/jobs/archive_post_auction_pipeline_job_test.rb
# ==============================================================================

require "test_helper"

class ArchivePostAuctionPipelineJobTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "arch-#{SecureRandom.hex(4)}@example.com", password: "password123456")
    PipelineStage.seed_for!(@user)
    @target_stage   = @user.pipeline_stages.find_by!(name: "Target")
    @won_stage      = @user.pipeline_stages.find_by!(system_key: PipelineStage::SYSTEM_KEY_WON)
    @archived_stage = @user.pipeline_stages.find_by!(system_key: PipelineStage::SYSTEM_KEY_ARCHIVED)
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  def make_parcel(sale_date:, county: "Polk", state: "FL")
    parcel = Parcel.create!(
      state:     state,
      county:    county,
      parcel_id: "TEST-#{SecureRandom.hex(4)}",
      address:   "200 Oak Ave"
    )
    auction = Auction.find_or_create_by!(
      state: state, county: county, sale_date: sale_date
    ) { |a| a.auction_type = "tax_deed"; a.status = "completed" }
    parcel.update!(auction_id: auction.id)
    parcel
  end

  def add_to_pipeline(parcel, stage:)
    PipelineProperty.create!(
      user: @user, parcel: parcel,
      pipeline_stage: stage, position: 0
    )
  end

  # ── Tests ──────────────────────────────────────────────────────────────

  test "moves to Archived when sale_date is older than 7 days" do
    parcel = make_parcel(sale_date: Date.current - 8.days)
    pp     = add_to_pipeline(parcel, stage: @target_stage)

    ArchivePostAuctionPipelineJob.new.perform

    pp.reload
    assert_equal @archived_stage.id, pp.pipeline_stage_id
  end

  test "does NOT move when sale_date is exactly 7 days ago (boundary)" do
    parcel = make_parcel(sale_date: Date.current - 7.days)
    pp     = add_to_pipeline(parcel, stage: @target_stage)

    ArchivePostAuctionPipelineJob.new.perform

    pp.reload
    assert_equal @target_stage.id, pp.pipeline_stage_id,
                 "El cutoff es estricto < (today - 7d), no <="
  end

  test "does NOT move recent past auctions (within 7 days grace)" do
    parcel = make_parcel(sale_date: Date.current - 3.days)
    pp     = add_to_pipeline(parcel, stage: @target_stage)

    ArchivePostAuctionPipelineJob.new.perform

    pp.reload
    assert_equal @target_stage.id, pp.pipeline_stage_id
  end

  test "does NOT move future auctions" do
    parcel = make_parcel(sale_date: Date.current + 5.days)
    pp     = add_to_pipeline(parcel, stage: @target_stage)

    ArchivePostAuctionPipelineJob.new.perform

    pp.reload
    assert_equal @target_stage.id, pp.pipeline_stage_id
  end

  test "respects 'Won' stage — never archives a winning property" do
    parcel = make_parcel(sale_date: Date.current - 30.days)
    pp     = add_to_pipeline(parcel, stage: @won_stage)

    ArchivePostAuctionPipelineJob.new.perform

    pp.reload
    assert_equal @won_stage.id, pp.pipeline_stage_id,
                 "Won es decisión del usuario; el job nunca lo sobrescribe"
  end

  test "skips cards already in Archived (no re-move)" do
    parcel = make_parcel(sale_date: Date.current - 30.days)
    pp     = add_to_pipeline(parcel, stage: @archived_stage)
    original_position = pp.position

    ArchivePostAuctionPipelineJob.new.perform

    pp.reload
    assert_equal @archived_stage.id, pp.pipeline_stage_id
    assert_equal original_position, pp.position, "No re-shuffles archived cards"
  end

  test "moves multiple eligible cards in one run" do
    p1 = make_parcel(sale_date: Date.current - 10.days)
    p2 = make_parcel(sale_date: Date.current - 20.days)
    add_to_pipeline(p1, stage: @target_stage)
    add_to_pipeline(p2, stage: @user.pipeline_stages.find_by!(name: "Due Diligence"))

    ArchivePostAuctionPipelineJob.new.perform

    @user.pipeline_properties.each do |pp|
      assert_equal @archived_stage.id, pp.pipeline_stage_id
    end
  end

  test "skips silently if user has no stage with system_key='archived'" do
    # Usuario "legacy" sin re-seed: borramos su stage Archived simulando estado
    # previo a la migración 20260503100000.
    @archived_stage.destroy!

    parcel = make_parcel(sale_date: Date.current - 30.days)
    pp     = add_to_pipeline(parcel, stage: @target_stage)

    assert_nothing_raised do
      ArchivePostAuctionPipelineJob.new.perform
    end

    pp.reload
    assert_equal @target_stage.id, pp.pipeline_stage_id, "queda en su stage original"
  end

  test "does not affect other users" do
    other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.com", password: "password123456")
    PipelineStage.seed_for!(other)
    other_target = other.pipeline_stages.find_by!(name: "Target")

    parcel = make_parcel(sale_date: Date.current - 30.days)
    other_pp = PipelineProperty.create!(
      user: other, parcel: parcel,
      pipeline_stage: other_target, position: 0
    )
    my_pp = add_to_pipeline(parcel, stage: @target_stage)

    ArchivePostAuctionPipelineJob.new.perform

    other_pp.reload
    my_pp.reload
    assert_equal other.pipeline_stages.find_by!(system_key: "archived").id, other_pp.pipeline_stage_id
    assert_equal @archived_stage.id, my_pp.pipeline_stage_id
  end
end
