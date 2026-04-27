# frozen_string_literal: true

class ViewedParcel < ApplicationRecord
  belongs_to :user
  belongs_to :parcel

  scope :unlocked, -> { where(unlocked: true) }

  def self.unlocked?(user_id:, parcel_id:)
    unlocked.exists?(user_id: user_id, parcel_id: parcel_id)
  end
end
