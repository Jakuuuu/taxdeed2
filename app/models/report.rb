# frozen_string_literal: true

class Report < ApplicationRecord
  belongs_to :user
  belongs_to :parcel

  VALID_TYPES = %w[avm property_scope title_search].freeze
  # NOTE: "otc" excluido de esta version
end