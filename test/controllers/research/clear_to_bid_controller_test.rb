# frozen_string_literal: true

require "test_helper"

module Research
  # ══════════════════════════════════════════════════════════════════════════
  # Spec de seguridad — Rama 6: Clear-to-Bid
  # ══════════════════════════════════════════════════════════════════════════
  # Cubre las barreras anti-fuga descritas en
  # software/rules/clear_to_bid/security_barriers.md.
  # Cualquier regresión aquí = breach del paywall.
  # ══════════════════════════════════════════════════════════════════════════
  class ClearToBidControllerTest < ActionDispatch::IntegrationTest
    setup do
      @secret_address     = "1234 Confidential Lane"
      @secret_parcel_id   = "REGRID-XYZ-9999"
      @secret_opening_bid = 12_500.0

      # Parcel debe estar en el scope clear_to_bid → grade ∈ %w[viable optimo]
      @parcel = Parcel.create!(
        state:              "FL",
        county:             "Miami-Dade",
        parcel_id:          @secret_parcel_id,
        address:            @secret_address,
        latitude:           25.7617,
        longitude:          -80.1918,
        opening_bid:        @secret_opening_bid,
        clear_to_bid_grade: "viable"
      )

      @user = User.create!(
        email:                 "buyer@example.com",
        password:              "password123",
        password_confirmation: "password123"
      )
    end

    # ── Auth gate ────────────────────────────────────────────────────────
    test "unauthenticated user is redirected to login" do
      get research_clear_to_bid_path
      assert_redirected_to new_user_session_path
    end

    # ── Trial → teaser only ──────────────────────────────────────────────
    test "trial user receives parcels_teaser, NOT parcels_full" do
      Subscription.create!(user: @user, plan_name: "standard", status: "trial")
      sign_in_as @user

      get research_clear_to_bid_path
      assert_response :success

      assert_not_nil assigns(:parcels_teaser)
      assert_nil assigns(:parcels_full)
      assert assigns(:upgrade_required)
    end

    # ── Premier active → full payload ────────────────────────────────────
    test "premier active user receives parcels_full" do
      Subscription.create!(user: @user, plan_name: "premier", status: "active")
      sign_in_as @user

      get research_clear_to_bid_path
      assert_response :success

      assert_not_nil assigns(:parcels_full)
      assert_nil assigns(:parcels_teaser)
      assert_not assigns(:upgrade_required)
    end

    # ── Premier canceled → blocked by require_active_subscription! ───────
    # require_active_subscription! ya redirige antes de llegar a `show`.
    # Este test asegura defensa en profundidad: si en el futuro se relaja
    # el guard, NUNCA debe llegar a @parcels_full.
    test "premier canceled user does NOT reach parcels_full" do
      Subscription.create!(user: @user, plan_name: "premier", status: "canceled")
      sign_in_as @user

      get research_clear_to_bid_path

      if response.redirect?
        # Esperado: redirect a paywall por require_active_subscription!
        assert_match(/subscription/i, response.location)
      else
        # Si el guard se relajó, el payload NUNCA debe ser full.
        assert_nil assigns(:parcels_full)
      end
    end

    # ── Pro plan (paid pero NO Premier) → teaser ─────────────────────────
    test "pro active user receives parcels_teaser, NOT parcels_full" do
      Subscription.create!(user: @user, plan_name: "pro", status: "active")
      sign_in_as @user

      get research_clear_to_bid_path
      assert_response :success

      assert_not_nil assigns(:parcels_teaser)
      assert_nil assigns(:parcels_full)
    end

    # ── Anti-leak en HTML: address NUNCA aparece para no-Premier ─────────
    test "response body does NOT contain parcel address for non-premier" do
      Subscription.create!(user: @user, plan_name: "pro", status: "active")
      sign_in_as @user

      get research_clear_to_bid_path
      assert_response :success

      assert_no_match(/#{Regexp.escape(@secret_address)}/, @response.body,
        "Sensitive address leaked into HTML for non-premier user")
      assert_no_match(/#{Regexp.escape(@secret_parcel_id)}/, @response.body,
        "Sensitive external parcel_id leaked into HTML for non-premier user")
      assert_no_match(/12,?500/, @response.body,
        "Opening bid leaked into HTML for non-premier user")
    end

    # ── Anti-bypass: ?parcel_id= para no-Premier → redirect silencioso ───
    test "non-premier with parcel_id param is redirected to paywall" do
      Subscription.create!(user: @user, plan_name: "pro", status: "active")
      sign_in_as @user

      get research_clear_to_bid_path, params: { parcel_id: @parcel.id }
      assert_redirected_to subscription_required_path
    end

    # ── ?force=1 ignorado (premier sigue premier, otros siguen otros) ────
    test "force param does not elevate non-premier to full payload" do
      Subscription.create!(user: @user, plan_name: "standard", status: "active")
      sign_in_as @user

      get research_clear_to_bid_path, params: { force: 1 }
      assert_response :success
      assert_nil assigns(:parcels_full)
      assert_not_nil assigns(:parcels_teaser)
    end

    # ── Deficiente NO aparece en el catálogo ─────────────────────────────
    test "deficiente parcels are excluded from clear_to_bid scope" do
      Parcel.create!(
        state: "FL", county: "Lee", parcel_id: "DEFICIENTE-1",
        address: "Bad Plot 1", clear_to_bid_grade: "deficiente"
      )

      Subscription.create!(user: @user, plan_name: "premier", status: "active")
      sign_in_as @user

      get research_clear_to_bid_path
      ids = Array(assigns(:parcels_full)).map { |h| h[:id] }
      assert_includes ids, @parcel.id
      assert_not_includes ids, Parcel.find_by(parcel_id: "DEFICIENTE-1").id
    end

    private

    def sign_in_as(user)
      post user_session_path, params: {
        user: { email: user.email, password: "password123" }
      }
    end
  end
end
