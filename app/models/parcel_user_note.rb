# frozen_string_literal: true

class ParcelUserNote < ApplicationRecord
  belongs_to :user
  belongs_to :parcel

  validates :body, presence: true, length: { maximum: 2000 }

  scope :for_user_parcel, ->(user, parcel) {
    where(user: user, parcel: parcel).order(created_at: :asc)
  }

  scope :latest_first, -> { order(created_at: :desc) }
end
