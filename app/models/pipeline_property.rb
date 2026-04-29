# frozen_string_literal: true

class PipelineProperty < ApplicationRecord
  belongs_to :user
  belongs_to :parcel
  belongs_to :pipeline_stage

  validates :parcel_id, uniqueness: { scope: :user_id, message: "already in pipeline" }

  scope :ordered, -> { order(:position) }

  # Move property to a new stage with optional position.
  # Syncs CRM tag if the target stage has a crm_tag_map.
  def move_to!(stage, position: nil)
    self.pipeline_stage = stage
    self.position = position || stage.pipeline_properties.count
    save!

    # Bidirectional sync: Pipeline → Mini CRM tag
    if stage.crm_tag_map.present?
      ParcelUserTag.upsert_for!(user: user, parcel: parcel, tag: stage.crm_tag_map)
    end
  end
end
