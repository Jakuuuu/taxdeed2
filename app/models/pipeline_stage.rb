# frozen_string_literal: true

class PipelineStage < ApplicationRecord
  belongs_to :user
  has_many :pipeline_properties, dependent: :destroy

  validates :name, presence: true, length: { maximum: 100 }
  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:position) }

  SYSTEM_KEY_ARCHIVED = "archived"
  SYSTEM_KEY_WON      = "won"

  DEFAULT_STAGES = [
    { name: "Target",        emoji: "🎯", color: "var(--accent)",           position: 0, is_default: true, crm_tag_map: "target",    system_key: nil },
    { name: "Due Diligence", emoji: "🔍", color: "var(--warning)",          position: 1, is_default: true, crm_tag_map: "diligence", system_key: nil },
    { name: "Ready to Bid",  emoji: "✅", color: "var(--success)",          position: 2, is_default: true, crm_tag_map: "ready",     system_key: nil },
    { name: "Dismissed",     emoji: "❌", color: "var(--ink-3)",            position: 3, is_default: true, crm_tag_map: "dismissed", system_key: nil },
    { name: "Won",           emoji: "🏆", color: "oklch(0.55 0.16 145)",   position: 4, is_default: true, crm_tag_map: nil,         system_key: SYSTEM_KEY_WON },
    { name: "Archived",      emoji: "📦", color: "var(--ink-4)",            position: 5, is_default: true, crm_tag_map: nil,         system_key: SYSTEM_KEY_ARCHIVED }
  ].freeze

  # Seed default stages on first access. Idempotent.
  def self.seed_for!(user)
    return if user.pipeline_stages.any?

    DEFAULT_STAGES.each { |attrs| user.pipeline_stages.create!(attrs) }
  end
end
