# frozen_string_literal: true

module Research
  class ParcelsController < BaseController
    def index
      @auctions = Auction.order(sale_date: :asc)
      @parcels  = Parcel.includes(:auction)

      @parcels = @parcels.where(auction_id: params[:auction_id]) if params[:auction_id].present?
      @parcels = @parcels.where("address ILIKE ?", "%#{params[:q]}%") if params[:q].present?
      @parcels = @parcels.order(created_at: :desc).page(params[:page]).per(25)
    end

    def show
      @parcel = Parcel.includes(:auction, :parcel_liens).find(params[:id])
    end
  end
end