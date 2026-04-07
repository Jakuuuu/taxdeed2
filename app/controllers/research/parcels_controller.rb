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
    end

    # GET /research/parcels/:id
    # Ficha de Propiedad — siempre render como drawer (XHR) o página completa
    def show
      @parcel = Parcel.find(params[:id])
      @auction = @parcel.auction

      # ── Mini CRM (transversal) ────────────────────────────
      @user_tag  = current_user.user_tags.find_by(parcel: @parcel)
      @user_note = current_user.user_notes.find_by(parcel: @parcel)

      render layout: false if request.xhr?
    end

    # POST /research/parcels/:id/request_report
    def request_report
      @parcel = Parcel.find(params[:id])
      sub     = current_user.subscription

      if sub.nil? || sub.used_parcels >= sub.limit_parcels
        redirect_to research_parcel_path(@parcel), alert: "Report limit reached. Upgrade your plan."
        return
      end

      existing = current_user.report_requests.find_by(parcel: @parcel, status: %w[pending processing])
      if existing
        redirect_to research_parcel_path(@parcel), notice: "A report for this parcel is already being processed."
        return
      end

      report = current_user.report_requests.create!(
        parcel: @parcel,
        status: "pending",
        requested_at: Time.current
      )
      sub.increment!(:used_parcels)

      redirect_to research_parcel_path(@parcel), notice: "Report ##{report.id} requested successfully."
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
      scope = scope.search_text(params[:q])       if params[:q].present?
      scope = scope.by_county(params[:county])     if params[:county].present?
      scope = scope.by_state(params[:filter_state]) if params[:filter_state].present?
      scope = scope.min_bid(params[:min_bid])      if params[:min_bid].present?
      scope = scope.max_bid(params[:max_bid])      if params[:max_bid].present?
      scope = scope.where(property_type: params[:property_type]) if params[:property_type].present?
      scope
    end
  end
end