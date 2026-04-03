# frozen_string_literal: true

module Research
  class ParcelsController < BaseController
    PER_PAGE_OPTIONS = [25, 50, 100].freeze

    def index
      @auctions  = Auction.visible.order(sale_date: :asc)
      @per_page  = PER_PAGE_OPTIONS.include?(params[:per_page].to_i) ? params[:per_page].to_i : 25

      if params[:auction_id].present?
        @auction = Auction.find_by(id: params[:auction_id])
        scope    = Parcel.for_auction(@auction&.id)
        scope    = apply_parcel_filters(scope)
        @parcels = scope.order(created_at: :desc).page(params[:page]).per(@per_page)
      else
        @parcels = Parcel.none.page(1).per(25)
        @auction = nil
      end
    end

    def show
      @parcel = Parcel.includes(:auction, :parcel_liens).find(params[:id])

      subscription = current_user.subscription
      already_seen = ViewedParcel.exists?(
        user_id: current_user.id,
        parcel_id: @parcel.id
      )

      unless already_seen
        if subscription.can_use?(:parcels)
          subscription.increment_usage!(:parcels)
          ViewedParcel.create!(user: current_user, parcel: @parcel)
        else
          respond_to do |format|
            format.html { redirect_to research_parcels_path, alert: "parcel_limit_reached" }
            format.json { render json: { error: "parcel_limit_reached", limit: subscription.limit_parcels }, status: :payment_required }
          end
          return
        end
      end

      @reports = Report.for_parcel(@parcel.id).where(user: current_user).latest_first
      @api_key = ENV["GOOGLE_MAPS_API_KEY"]

      respond_to do |format|
        format.html
        format.json { render json: parcel_json(@parcel, @reports) }
      end
    end

    private

    def apply_parcel_filters(scope)
      scope = scope.search_text(params[:q])    if params[:q].present?
      scope = scope.by_county(params[:county]) if params[:county].present?
      scope = scope.min_bid(params[:min_bid])  if params[:min_bid].present?
      scope = scope.max_bid(params[:max_bid])  if params[:max_bid].present?
      scope
    end

    def parcel_json(parcel, reports)
      {
        id:               parcel.id,
        address:          parcel.address,
        full_address:     parcel.full_address,
        parcel_id:        parcel.parcel_id,
        county:           parcel.county,
        state:            parcel.state,
        zip_code:         parcel.zip_code,
        opening_bid:      parcel.opening_bid&.to_f,
        assessed_value:   parcel.assessed_value&.to_f,
        market_value:     parcel.market_value&.to_f,
        land_value:       parcel.land_value&.to_f,
        improvement_value: parcel.improvement_value&.to_f,
        delinquent_amount: parcel.delinquent_amount&.to_f,
        tax_year:         parcel.tax_year,
        year_built:       parcel.year_built,
        living_area_sqft: parcel.living_area_sqft,
        lot_size_sqft:    parcel.lot_size_sqft,
        bedrooms:         parcel.bedrooms,
        bathrooms:        parcel.bathrooms,
        property_type:    parcel.property_type,
        land_use:         parcel.land_use,
        zoning:           parcel.zoning,
        latitude:         parcel.latitude&.to_f,
        longitude:        parcel.longitude&.to_f,
        max_bid_30:       parcel.max_bid_30,
        max_bid_35:       parcel.max_bid_35,
        adjusted_value_16: parcel.adjusted_value_16,
        sale_date:        parcel.auction&.sale_date&.strftime("%Y-%m-%d"),
        liens:            parcel.parcel_liens.map { |l|
          { lender: l.lender, lien_type: l.lien_type, amount: l.amount&.to_f,
            recorded_date: l.recorded_date&.strftime("%Y-%m-%d"), status: l.status }
        },
        reports:          reports.map { |r|
          { id: r.id, type: r.report_type, status: r.status, file_url: r.file_url }
        }
      }
    end
  end
end