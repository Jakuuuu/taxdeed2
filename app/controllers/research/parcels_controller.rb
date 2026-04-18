# frozen_string_literal: true

module Research
  class ParcelsController < BaseController
    before_action :require_active_subscription!
    PER_PAGE_OPTIONS = [25, 50, 100].freeze

    # GET /research/parcels
    def index
      # ── MOTOR DE TIEMPO: Rama 2 SIEMPRE muestra solo subastas activas.
      # (sale_date >= hoy). No se expone opción Past al usuario.

      @auctions_by_state = Auction.visible
                                  .order(state: :asc, sale_date: :asc)
                                  .group_by(&:state)

      # DRY — Unified county-grouped data for the "Seleccionar condado" picker.
      # Uses time-filtered scope so picker reflects only active auction counties.
      @picker_counties_by_state = helpers.counties_with_auctions_grouped(Auction.active_visible)

      @per_page = PER_PAGE_OPTIONS.include?(params[:per_page].to_i) ? params[:per_page].to_i : 25
      @available_states = Auction.visible.distinct.pluck(:state).compact.sort

      if params[:auction_id].present?
        # ── Modo Auction: una subasta específica ──────────────────
        @auction = Auction.find_by(id: params[:auction_id])
        @selected_state = @auction&.state
        scope    = Parcel.for_auction(@auction&.id)
        scope    = apply_parcel_filters(scope)
        @parcels = scope.order(created_at: :desc).page(params[:page]).per(@per_page)

      elsif params[:county].present? && params[:state].present?
        # ── Modo County: parcelas de un condado específico ─────────
        @selected_state  = params[:state]
        @selected_county = params[:county]
        auction_ids = Auction.active_visible
                        .by_state(@selected_state)
                        .where(county: @selected_county)
                        .pluck(:id)
        scope    = Parcel.where(auction_id: auction_ids)
        scope    = apply_parcel_filters(scope)
        @parcels = scope.order(created_at: :desc).page(params[:page]).per(@per_page)
        @auction = nil

      elsif params[:state].present?
        # ── Modo State: todas las parcelas de un estado ───────────
        @selected_state = params[:state]
        @state_auctions = Auction.active_visible.by_state(@selected_state).order(sale_date: :asc)
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

      # ── Admin God Mode: bypass de Paywall ──────────────────────────────
      # Si el usuario es admin, la ficha se trata como desbloqueada SIN
      # tocar la tabla viewed_parcels ni descontar créditos.
      @admin_override = current_user.admin?

      if @admin_override
        @unlocked = true
      else
        # ── Blur Paywall: check if user has already unlocked this parcel ──
        @unlocked = ViewedParcel.exists?(user_id: current_user.id, parcel_id: @parcel.id)
      end

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

      # ── Admin God Mode: bypass instantáneo ─────────────────────────────
      # No consume créditos, no crea registro en viewed_parcels.
      if current_user.admin?
        render json: { unlocked: true, message: "Admin override — no credits consumed" } and return
      end

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

    # GET /research/parcels/county_overview.json
    # Phase 1: Geographic Overview — aggregated county-level data for map pins
    # MOTOR DE TIEMPO: Filtra por subastas activas (sale_date >= hoy) por defecto
    def county_overview
      auctions = Auction.active_visible.includes(:parcels)

      grouped = auctions.group_by { |a| [a.county, a.state] }

      results = grouped.filter_map do |(county, state), auction_list|
        parcel_count = auction_list.sum { |a| a.parcel_count || 0 }
        total_amount = auction_list.sum { |a| a.total_amount.to_f }
        auction_count = auction_list.size

        # Coordenadas: usar las del auction si existen, o promedio de parcelas geocodificadas
        lat, lng = nil, nil
        auction_with_coords = auction_list.find { |a| a.latitude.present? && a.longitude.present? }
        if auction_with_coords
          lat = auction_with_coords.latitude.to_f
          lng = auction_with_coords.longitude.to_f
        else
          # Fallback: promedio de parcelas con coordenadas
          auction_ids = auction_list.map(&:id)
          coords = Parcel.where(auction_id: auction_ids).has_coords
                         .pluck(:latitude, :longitude)
          if coords.any?
            lat = coords.sum { |c| c[0].to_f } / coords.size
            lng = coords.sum { |c| c[1].to_f } / coords.size
          end
        end

        # Skip counties without any coordinates
        next unless lat && lng

        {
          county:        county,
          state:         state,
          lat:           lat.round(6),
          lng:           lng.round(6),
          parcel_count:  parcel_count,
          auction_count: auction_count,
          total_amount:  total_amount.round(2),
          sale_dates:    auction_list.filter_map { |a| a.sale_date&.strftime("%b %d, %Y") }
        }
      end

      response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
      response.headers["Pragma"]        = "no-cache"
      response.headers["Expires"]       = "0"

      render json: results
    end

    # GET /research/parcels/map_data.json
    # Supports auction_id, state, or county+state as parameters
    # MOTOR DE TIEMPO: Respects status filter for county/state modes
    def map_data
      if params[:auction_id].present?
        auction = Auction.find_by(id: params[:auction_id])
        unless auction
          render json: { error: "Auction not found" }, status: :not_found and return
        end
        parcels = Parcel.for_auction(auction.id).has_coords

      elsif params[:county].present? && params[:state].present?
        # County-level drill-down: only parcels for this specific county
        auction_ids = Auction.active_visible.by_state(params[:state])
                             .where(county: params[:county]).pluck(:id)
        parcels = Parcel.where(auction_id: auction_ids).has_coords

      elsif params[:state].present?
        auction_ids = Auction.active_visible.by_state(params[:state]).pluck(:id)
        parcels = Parcel.where(auction_id: auction_ids).has_coords

      else
        render json: { error: "auction_id, state, or county+state is required" }, status: :bad_request and return
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

    # GET /research/parcels/parcels_list.json
    # Phase 2 async parcel list — paginated, filterable
    # MOTOR DE TIEMPO: Respects status filter
    def parcels_list
      per_page = PER_PAGE_OPTIONS.include?(params[:per_page].to_i) ? params[:per_page].to_i : 25

      if params[:auction_id].present?
        auction = Auction.find_by(id: params[:auction_id])
        scope = auction ? Parcel.for_auction(auction.id) : Parcel.none
      elsif params[:county].present? && params[:state].present?
        auction_ids = Auction.active_visible.by_state(params[:state])
                             .where(county: params[:county]).pluck(:id)
        scope = Parcel.where(auction_id: auction_ids)
      elsif params[:state].present?
        auction_ids = Auction.active_visible.by_state(params[:state]).pluck(:id)
        scope = Parcel.where(auction_id: auction_ids)
      else
        render json: { parcels: [], meta: { total: 0, page: 1, pages: 0 } } and return
      end

      scope = apply_parcel_filters(scope)
      paginated = scope.includes(:auction).order(created_at: :desc).page(params[:page]).per(per_page)

      render json: {
        parcels: paginated.map { |p|
          {
            id:              p.id,
            address:         p.address || '—',
            city:            p.city,
            county:          p.county,
            state:           p.state,
            zip:             p.zip_code,
            parcel_id:       p.parcel_id,
            opening_bid:     p.opening_bid&.to_f,
            assessed_value:  p.assessed_value&.to_f,
            max_bid_30:      p.max_bid_30&.to_f,
            delinquent_amount: p.delinquent_amount&.to_f,
            property_type:   p.property_type,
            sale_date:       p.auction&.sale_date&.strftime("%b %d, %Y"),
            has_coords:      p.has_coords?,
            show_path:       "/research/parcels/#{p.id}"
          }
        },
        meta: {
          total:     paginated.total_count,
          page:      paginated.current_page,
          pages:     paginated.total_pages,
          per_page:  per_page,
          from:      [paginated.offset_value + 1, paginated.total_count].min,
          to:        [paginated.offset_value + paginated.length, paginated.total_count].min
        }
      }
    end

    private

    # ── Motor de Tiempo: Rama 2 SIEMPRE usa active_visible ────────────────
    # No se expone filtro de status al usuario en esta rama.

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