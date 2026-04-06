# frozen_string_literal: true

class ParcelUserTag < ApplicationRecord
  belongs_to :user
  belongs_to :parcel

  VALID_TAGS = %w[
    ya_visto
    hacer_seguimiento
    potencial
    en_evaluacion
    descartado
  ].freeze

  TAG_LABELS = {
    "ya_visto"           => "Already Seen",
    "hacer_seguimiento"  => "Follow Up",
    "potencial"          => "Potential",
    "en_evaluacion"      => "Evaluating",
    "descartado"         => "Discarded"
  }.freeze

  TAG_COLORS = {
    "ya_visto"           => "#6C757D",
    "hacer_seguimiento"  => "#0D6EFD",
    "potencial"          => "#198754",
    "en_evaluacion"      => "#FFC107",
    "descartado"         => "#DC3545"
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
