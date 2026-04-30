# frozen_string_literal: true

module Research
  class PipelinePropertiesController < BaseController
    before_action :set_pipeline_property, only: [:move, :update_note, :destroy]

    # POST /research/portfolio/properties/bulk
    # Adds multiple parcels to the pipeline at once (max 100).
    def bulk_create
      ids = Array(params[:parcel_ids]).map(&:to_i).uniq.first(100)
      return render(json: { success: false, error: "invalid" }, status: :unprocessable_entity) if ids.blank?

      stage = current_user.pipeline_stages.where(is_default: true).order(:position).first
      unless stage
        PipelineStage.seed_for!(current_user)
        stage = current_user.pipeline_stages.where(is_default: true).order(:position).first
      end

      added = 0
      skipped = 0
      Parcel.where(id: ids).find_each do |parcel|
        pp = current_user.pipeline_properties.find_or_initialize_by(parcel: parcel)
        if pp.new_record?
          pp.pipeline_stage = stage
          pp.position = stage.pipeline_properties.count
          pp.save!
          added += 1
        else
          skipped += 1
        end
      end

      render json: { success: true, added: added, skipped: skipped }
    end

    # POST /research/portfolio/properties
    # Adds a parcel to the pipeline (first default stage = Target).
    def create
      @parcel = Parcel.find(params[:parcel_id])
      stage = current_user.pipeline_stages.where(is_default: true).order(:position).first

      # Auto-seed stages if none exist
      unless stage
        PipelineStage.seed_for!(current_user)
        stage = current_user.pipeline_stages.where(is_default: true).order(:position).first
      end

      @pp = current_user.pipeline_properties.find_or_initialize_by(parcel: @parcel)
      if @pp.new_record?
        @pp.pipeline_stage = stage
        @pp.position = stage.pipeline_properties.count
        @pp.save!
        render json: { success: true, action: "added", stage: stage.name }, status: :created
      else
        render json: { success: true, action: "already_exists", stage: @pp.pipeline_stage.name }
      end
    end

    # PATCH /research/portfolio/properties/:id/move
    # Drag & drop: move property to a new stage with position.
    def move
      stage = current_user.pipeline_stages.find(params[:stage_id])
      position = params[:position]&.to_i

      @pp.move_to!(stage, position: position)

      render json: {
        success: true,
        synced_tag: stage.crm_tag_map,
        stage_name: stage.name
      }
    end

    # PATCH /research/portfolio/properties/:id/note
    # Inline note editing from pipeline card.
    def update_note
      note = current_user.parcel_user_notes.find_or_initialize_by(parcel: @pp.parcel)
      note.body = params[:body]

      if note.save
        # Also store on the pipeline_property for inline display
        @pp.update_column(:notes, params[:body])
        render json: { success: true, body: note.body }
      else
        render json: { success: false, errors: note.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /research/portfolio/properties/:id
    # Removes a property from the pipeline.
    def destroy
      @pp.destroy!
      render json: { success: true }
    end

    private

    def set_pipeline_property
      @pp = current_user.pipeline_properties.find(params[:id])
    end
  end
end
