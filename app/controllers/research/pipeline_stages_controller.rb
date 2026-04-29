# frozen_string_literal: true

module Research
  class PipelineStagesController < BaseController
    before_action :set_stage, only: [:update, :destroy]

    # POST /research/portfolio/stages
    def create
      @stage = current_user.pipeline_stages.new(stage_params)
      @stage.position = current_user.pipeline_stages.maximum(:position).to_i + 1

      if @stage.save
        render json: { success: true, stage: stage_json(@stage) }, status: :created
      else
        render json: { success: false, errors: @stage.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PATCH /research/portfolio/stages/:id
    def update
      if @stage.update(stage_params)
        render json: { success: true, stage: stage_json(@stage) }
      else
        render json: { success: false, errors: @stage.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /research/portfolio/stages/:id
    def destroy
      if @stage.is_default?
        render json: { success: false, error: "Cannot delete default stages" }, status: :forbidden
        return
      end

      # Move orphaned properties to the first default stage
      fallback = current_user.pipeline_stages.where(is_default: true).order(:position).first
      if fallback
        @stage.pipeline_properties.update_all(pipeline_stage_id: fallback.id)
      end

      @stage.destroy!
      render json: { success: true, moved_to: fallback&.name }
    end

    private

    def set_stage
      @stage = current_user.pipeline_stages.find(params[:id])
    end

    def stage_params
      params.permit(:name, :emoji, :color, :position)
    end

    def stage_json(stage)
      {
        id: stage.id,
        name: stage.name,
        emoji: stage.emoji,
        color: stage.color,
        position: stage.position,
        is_default: stage.is_default,
        crm_tag_map: stage.crm_tag_map,
        count: stage.pipeline_properties.count
      }
    end
  end
end
