# frozen_string_literal: true

module Research
  class ParcelUserTagsController < BaseController
    before_action :require_active_subscription!

    # POST /research/parcel_user_tags/bulk
    # Assigns the given tag to multiple parcels at once (max 100).
    def bulk
      ids = Array(params[:parcel_ids]).map(&:to_i).uniq.first(100)
      tag = params[:tag]

      return render(json: { success: false, error: "invalid" }, status: :unprocessable_entity) if ids.blank? || tag.blank?

      count = 0
      Parcel.where(id: ids).find_each do |parcel|
        existing = current_user.parcel_user_tags.find_by(parcel_id: parcel.id)
        if existing
          existing.update!(tag: tag)
        else
          current_user.parcel_user_tags.create!(parcel_id: parcel.id, tag: tag)
        end
        count += 1

        # ── Bidirectional Sync: bulk tag → Pipeline stage ──
        stage = current_user.pipeline_stages.find_by(crm_tag_map: tag)
        if stage
          pp = PipelineProperty.find_or_initialize_by(user: current_user, parcel: parcel)
          pp.pipeline_stage = stage
          pp.position = stage.pipeline_properties.count unless pp.persisted?
          pp.save!
        end
      end

      render json: { success: true, count: count, tag: tag }
    end

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

      # ── Bidirectional Sync: Ficha → Pipeline ──────────────────────────
      # When a CRM tag is set/changed, move the property to the
      # matching pipeline stage (if it exists in the user's pipeline).
      if current_tag.present?
        stage = current_user.pipeline_stages.find_by(crm_tag_map: current_tag)
        if stage
          pp = PipelineProperty.find_or_initialize_by(user: current_user, parcel: @parcel)
          pp.pipeline_stage = stage
          pp.position = stage.pipeline_properties.count unless pp.persisted?
          pp.save!
        end
      end

      respond_to do |format|
        format.json { render json: { tag: current_tag } }
        format.html { redirect_back fallback_location: research_parcel_path(@parcel) }
      end
    end
  end
end
