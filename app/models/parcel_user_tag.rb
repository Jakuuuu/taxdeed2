# frozen_string_literal: true

class ParcelUserTag < ApplicationRecord
  belongs_to :user
  belongs_to :parcel

  VALID_TAGS = %w[
    target
    diligence
    ready
    dismissed
  ].freeze

  TAG_LABELS = {
    "target"     => "Target",
    "diligence"  => "Due Diligence",
    "ready"      => "Ready to Bid",
    "dismissed"  => "Dismissed"
  }.freeze

  TAG_COLORS = {
    "target"     => "#2E86C1",
    "diligence"  => "#E67E22",
    "ready"      => "#27AE60",
    "dismissed"  => "#6C757D"
  }.freeze

  validates :tag, inclusion: { in: VALID_TAGS, message: "%{value} is not a valid tag" }
  # Unicidad enforced vía unique index en BD (user_id, parcel_id)

  def label
    TAG_LABELS.fetch(tag, tag.humanize)
  end

  def color
    TAG_COLORS.fetch(tag, "#6C757D")
  end

  # UPSERT: un usuario solo puede tener un tag por parcela
  def self.upsert_for!(user:, parcel:, tag:)
    record = find_or_initialize_by(user: user, parcel: parcel)
    record.tag = tag
    record.save!
    record
  end
end
