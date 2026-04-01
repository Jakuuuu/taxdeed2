# frozen_string_literal: true

class ViewedParcel < ApplicationRecord
  belongs_to :user
  belongs_to :parcel
end