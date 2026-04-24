# frozen_string_literal: true

module Research
  # ══════════════════════════════════════════════════════════════════════════
  # LegalAgreementsController
  # ══════════════════════════════════════════════════════════════════════════
  # Handles the acceptance of the premium data legal disclaimer.
  #
  # Business Rule:
  #   Before viewing ANY unlocked premium property data, the user must
  #   explicitly accept the legal disclaimer. This is a one-time action
  #   recorded as an immutable timestamp (audit trail).
  #
  # Flow:
  #   1. User unlocks a property (existing flow — consumes credit)
  #   2. If `current_user.premium_disclaimer_accepted_at` is NULL,
  #      an overlay blocks the premium data with a legal disclaimer
  #   3. User checks the checkbox + clicks "Accept"
  #   4. POST hits this controller → records timestamp
  #   5. Turbo Stream replaces the premium data section (removes overlay)
  #
  # Security:
  #   - Inherits authentication + active subscription from BaseController
  #   - Only updates the current_user — no mass assignment risk
  #   - Idempotent: re-accepting is harmless (updates timestamp)
  # ══════════════════════════════════════════════════════════════════════════
  class LegalAgreementsController < BaseController
    # POST /research/legal_agreements/accept_premium_disclaimer
    def accept_premium_disclaimer
      current_user.update!(premium_disclaimer_accepted_at: Time.current)

      # Retrieve the parcel context to re-render the premium data section
      @parcel  = Parcel.find(params[:parcel_id])
      @auction = @parcel.auction

      # Re-evaluate unlock status (same logic as ParcelsController#show)
      @admin_override = current_user.admin?
      @unlocked = @admin_override || ViewedParcel.exists?(user_id: current_user.id, parcel_id: @parcel.id)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "premium-data-wrapper",
            partial: "research/parcels/premium_data",
            locals: { parcel: @parcel, unlocked: @unlocked, admin_override: @admin_override }
          )
        end
        format.html { redirect_to research_parcel_path(@parcel) }
      end
    end
  end
end
