# frozen_string_literal: true

module Research
  class ParcelsController < BaseController
    before_action :require_active_subscription!
    PER_PAGE_OPTIONS = [25, 50, 100].freeze

    # GET /research/parcels
    def index
      @auctions_by_state = Auction.visible
                                  .order(state: :asc, sale_date: :asc)
                                  .group_by(&:state)
      @per_page = PER_PAGE_OPTIONS.include?(params[:per_page].to_i) ? params[:per_page].to_i : 25
      @available_states = Auction.visible.distinct.pluck(:state).compact.sort

      if params[:auction_id].present?
        # ── Modo Auction: una subasta específica ──────────────────
        @auction = Auction.find_by(id: params[:auction_id])
        @selected_state = @auction&.state
        scope    = Parcel.for_auction(@auction&.id)
        scope    = apply_parcel_filters(scope)
        @parcels = scope.order(created_at: :desc).page(params[:page]).per(@per_page)

      elsif params[:state].present?
        # ── Modo State: todas las parcelas de un estado ───────────
        @selected_state = params[:state]
        @state_auctions = Auction.visible.by_state(@selected_state).order(sale_date: :asc)
        auction_ids = @state_auctions.pluck(:id)
        scope = Parcel.where(auction_id: auction_ids)
        scope = apply_parcel_filters(scope)
        @parcels = scope.order(created_at: :desc).page(params[:page]).per(@per_page)
        @auction = nil

      else
        # ── Sin contexto: pantalla de selección ───────────────────
        @parcels = Parcel.none.page(1).per(25)
        @auction = nil
      end

      @has_context = @auction.present? || @selected_state.present?

      # Persist last parcels context for "← Back" button in the Ficha
      session[:last_parcels_path] = request.url if @has_context
    end

    # GET /research/parcels/:id
    # Single Advanced Property Card — single column vertical view with Blur Paywall
    def show
      @parcel  = Parcel.find(params[:id])
      @auction = @parcel.auction

      # ── Blur Paywall: check if user has already unlocked this parcel ──
      @unlocked = ViewedParcel.exists?(user_id: current_user.id, parcel_id: @parcel.id)

      # ── Mini CRM (transversal — always visible regardless of paywall) ─
      @current_tag = current_user.parcel_user_tags.find_by(parcel_id: @parcel.id)
      @notes       = current_user.parcel_user_notes
                                 .where(parcel_id: @parcel.id)
                                 .order(created_at: :desc)

      render layout: false if request.xhr?
    end

    # POST /research/parcels/:id/unlock
    # Consumes 1 parcel credit and creates a ViewedParcel unlock record.
    # Basic property data (header) is always free. Advanced data requires unlock.
    def unlock
      @parcel = Parcel.find(params[:id])
      sub     = current_user.subscription

      # Already unlocked — return success without consuming another credit
      if ViewedParcel.exists?(user_id: current_user.id, parcel_id: @parcel.id)
        render json: { unlocked: true, message: "Already unlocked" } and return
      end

      # Check subscription
      unless sub&.active?
        render json: { unlocked: false, error: "Active subscription required to unlock properties." },
               status: :payment_required and return
      end

      # Check credit availability
      unless sub.can_use?(:parcels)
        render json: { unlocked: false, error: "No credits remaining. Please upgrade your plan." },
               status: :payment_required and return
      end

      # Consume credit + create unlock record atomically
      ActiveRecord::Base.transaction do
        sub.increment_usage!(:parcels)
        ViewedParcel.create!(user_id: current_user.id, parcel_id: @parcel.id)
      end

      render json: { unlocked: true }

    rescue => e
      Rails.logger.error "[Parcels#unlock] #{e.class}: #{e.message}"
      render json: { unlocked: false, error: "An error occurred. Please try again." },
             status: :unprocessable_entity
    end

    # GET /research/parcels/map_data.json
    # ⚠️ Soporta auction_id O state como parámetro
    def map_data
      if params[:auction_id].present?
        auction = Auction.find_by(id: params[:auction_id])
        unless auction
          render json: { error: "Auction not found" }, status: :not_found and return
        end
        parcels = Parcel.for_auction(auction.id).has_coords

      elsif params[:state].present?
        auction_ids = Auction.visible.by_state(params[:state]).pluck(:id)
        parcels = Parcel.where(auction_id: auction_ids).has_coords

      else
        render json: { error: "auction_id or state is required" }, status: :bad_request and return
      end

      parcels = parcels.select(
        :id, :address, :city, :county, :state, :zip_code,
        :parcel_id, :opening_bid, :latitude, :longitude,
        :property_type, :land_use
      )

      render json: parcels.map { |p|
        {
          id:            p.id,
          address:       p.address,
          city:          p.city,
          county:        p.county,
          state:         p.state,
          zip:           p.zip_code,
          parcel_id:     p.parcel_id,
          opening_bid:   p.opening_bid&.to_f,
          property_type: p.property_type,
          land_use:      p.land_use,
          lat:           p.latitude.to_f,
          lng:           p.longitude.to_f
        }
      }
    end

    private

    def apply_parcel_filters(scope)
      scope = scope.search_text(params[:q])        if params[:q].present?
      scope = scope.by_county(params[:county])      if params[:county].present?
      scope = scope.by_state(params[:filter_state]) if params[:filter_state].present?
      scope = scope.min_bid(params[:min_bid])       if params[:min_bid].present?
      scope = scope.max_bid(params[:max_bid])       if params[:max_bid].present?
      scope = scope.where(property_type: params[:property_type]) if params[:property_type].present?
      scope
    end
  end
end