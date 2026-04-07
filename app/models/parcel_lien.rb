# frozen_string_literal: true

class ParcelLien < ApplicationRecord
  belongs_to :parcel

  # La columna en BD es lender_name, pero la vista usa lien.lender
  alias_attribute :lender, :lender_name
end