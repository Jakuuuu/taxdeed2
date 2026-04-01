# frozen_string_literal: true

module Research
  class ParcelsController < ApplicationController
    before_action :require_active_subscription!

    def index
      @parcels = Parcel.includes(:auction).order(created_at: :desc).limit(20)
    end
  end
end