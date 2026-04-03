# frozen_string_literal: true

module Research
  class AuctionsController < BaseController

    def index
      @auctions = Auction.all
      @auctions = apply_filters(@auctions)
      @auctions = @auctions.order(sale_date: :asc)

      @states  = Auction.distinct.pluck(:state).compact.sort
      @counties = Auction.distinct.pluck(:county).compact.sort

      respond_to do |format|
        format.html
        format.json do
          render json: @auctions.map { |a| auction_json(a) }
        end
      end
    end

    def show
      @auction = Auction.includes(:parcels).find(params[:id])
      @parcels = @auction.parcels.order(:address)
    end

    private

    def apply_filters(scope)
      scope = scope.by_state(params[:state])   if params[:state].present?
      scope = scope.by_county(params[:county]) if params[:county].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.from_date(params[:from_date]) if params[:from_date].present?
      scope = scope.to_date(params[:to_date])   if params[:to_date].present?
      scope
    end

    def auction_json(auction)
      {
        id:           auction.id,
        jurisdiction: auction.jurisdiction,
        state:        auction.state,
        county:       auction.county,
        auction_type: "tax_deed",
        sale_date:    auction.sale_date&.strftime("%Y-%m-%d"),
        parcel_count: auction.parcel_count || 0,
        total_amount: auction.total_amount&.to_f || 0,
        status:       auction.status,
        latitude:     auction.latitude&.to_f,
        longitude:    auction.longitude&.to_f,
        bidding_url:  auction.bidding_url,
        parcels_url:  research_parcels_path(auction_id: auction.id)
      }
    end
  end
end
