# frozen_string_literal: true

module Research
  class ParcelUserTagsController < BaseController
    before_action :require_active_subscription!

    # POST /research/parcel_user_tags?parcel_id=:id&tag=:tag
    # Toggles a tag on a parcel for the current user.
    # If the user already has this tag on the parcel → removes it (toggle off).
    # If the user has a different tag → replaces it.
    # This is a "radio" style — one tag per user per parcel.
    def create
      @parcel = Parcel.find(params[:parcel_id])

      existing = current_user.parcel_user_tags.find_by(parcel_id: @parcel.id)

      if existing&.tag == params[:tag]
        # Toggle off: same tag clicked again → remove
        existing.destroy!
        current_tag = nil
      elsif existing
        # Replace existing tag
        existing.update!(tag: params[:tag])
        current_tag = params[:tag]
      else
        # Create new tag
        current_user.parcel_user_tags.create!(parcel_id: @parcel.id, tag: params[:tag])
        current_tag = params[:tag]
      end

      respond_to do |format|
        format.json { render json: { tag: current_tag } }
        format.html { redirect_back fallback_location: research_parcel_path(@parcel) }
      end
    end
  end
end
