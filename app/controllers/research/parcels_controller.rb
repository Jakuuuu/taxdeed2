# frozen_string_literal: true

module Research
  class ParcelsController < BaseController
    before_action :require_active_subscription!
    PER_PAGE_OPTIONS = [25, 50, 100].freeze

    # GET /research/parcels
    # ══════════════════════════════════════════════════════════════════════
    # TWO-PHASE FLOW ENFORCEMENT — Regla Arquitectónica Inquebrantable:
    #   Fase 1 → Landing: mapa de condados (county_overview.json)
    #   Fase 2 → Drill-down: SOLO con auction_id O county+state
    #
    # ELIMINADO: modo state-only (params[:state] sin county).
    # Cargar "All properties in Florida" está PROHIBIDO por diseño.
    # ══════════════════════════════════════════════════════════════════════
    def index
      # DRY data for the "Seleccionar condado" picker modal
      @picker_counties_by_state = helpers.counties_with_auctions_grouped(Auction.active_visible)

      @per_page = PER_PAGE_OPTIONS.include?(params[:per_page].to_i) ? params[:per_page].to_i : 25

      if params[:auction_id].present?
        # ── FASE 2 — Modo Auction: una subasta específica ──────────────
        @auction = Auction.find_by(id: params[:auction_id])
        @selected_state  = @auction&.state
        @selected_county = @auction&.county
        scope    = Parcel.for_auction(@auction&.id)
        scope    = apply_parcel_filters(scope)
        @parcels = scope.order(created_at: :desc).page(params[:page]).per(@per_page)

      elsif params[:county].present? && params[:state].present?
        # ── FASE 2 — Modo County: drill-down al condado seleccionado ───
        # ÚNICA vía legítima de llegar a Fase 2 sin auction_id.
        @selected_state  = params[:state]
        @selected_county = params[:county]
        auction_ids = Auction.active_visible
                        .by_state(@selected_state)
                        .by_county(@selected_county)
                        .pluck(:id)
        scope    = Parcel.where(auction_id: auction_ids)
        scope    = apply_parcel_filters(scope)
        @parcels = scope.order(created_at: :desc).page(params[:page]).per(@per_page)
        @auction = nil

      else
        # ── FASE 1 — Sin contexto: pantalla de selección (county overview) ──
        # Esto incluye params[:state] sin county — NO se carga nada masivo.
        # El mapa carga county_overview.json por Ajax. La tabla queda vacía.
        @parcels = Parcel.none.page(1).per(25)
        @auction = nil
      end

      @has_context = @auction.present? || (@selected_county.present? && @selected_state.present?)

      # Distinct land_use/property_type values for the Property Type filter dropdown
      @land_use_types = (
        Parcel.where.not(land_use: [nil, ""]).distinct.pluck(:land_use) +
        Parcel.where.not(property_type: [nil, ""]).distinct.pluck(:property_type)
      ).map(&:strip).uniq.sort

      # Persist last parcels context for "← Back" button in the Ficha
      session[:last_parcels_path] = request.url if @has_context
    end

    # GET /research/parcels/:id
    # Single Advanced Property Card — single column vertical view with Blur Paywall
    def show
      @parcel  = Parcel.find(params[:id])
      @auction = @parcel.auction

      # ── Admin God Mode: bypass de Paywall ──────────────────────────────
      @admin_override = current_user.admin?

      if @admin_override
        @unlocked = true
      else
        @unlocked = ViewedParcel.exists?(user_id: current_user.id, parcel_id: @parcel.id)
      end

      # ── Mini CRM (transversal — always visible regardless of paywall) ─
      @current_tag = current_user.parcel_user_tags.find_by(parcel_id: @parcel.id)
      @notes       = current_user.parcel_user_notes
                                 .where(parcel_id: @parcel.id)
                                 .order(created_at: :desc)

      # ── County Market Stat lookup (for "Conocer más sobre el condado" CTA) ─
      @county_market_stat = CountyMarketStat.find_by(
        "UPPER(state) = ? AND UPPER(county) = ?",
        @parcel.state.to_s.upcase,
        @parcel.county.to_s.upcase
      )

      render layout: false if request.xhr?
    end

    # POST /research/parcels/:id/unlock
    def unlock
      @parcel = Parcel.find(params[:id])

      if current_user.admin?
        render json: { unlocked: true, message: "Admin override — no credits consumed" } and return
      end

      sub = current_user.subscription

      if ViewedParcel.exists?(user_id: current_user.id, parcel_id: @parcel.id)
        render json: { unlocked: true, message: "Already unlocked" } and return
      end

      unless sub&.active?
        render json: { unlocked: false, error: "Active subscription required to unlock properties." },
               status: :payment_required and return
      end

      unless sub.can_use?(:parcels)
        render json: { unlocked: false, error: "No credits remaining. Please upgrade your plan." },
               status: :payment_required and return
      end

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

    # GET /research/parcels/:id/download_pdf
    # ══════════════════════════════════════════════════════════════════════
    # Genera y descarga el PDF de la ficha de propiedad on-the-fly.
    # Generación SÍNCRONA — el PDF es ligero (datos de BD, sin imágenes).
    # No se persiste en Active Storage ni se crea registro Report.
    #
    # Autorización:
    #   - Admin: siempre puede descargar
    #   - Usuario normal: requiere unlock + disclaimer aceptado
    # ══════════════════════════════════════════════════════════════════════
    def download_pdf
      @parcel  = Parcel.find(params[:id])

      # ── Autorización ──────────────────────────────────────────────
      unless current_user.admin? ||
             (ViewedParcel.exists?(user_id: current_user.id, parcel_id: @parcel.id) &&
              current_user.premium_disclaimer_accepted_at.present?)
        redirect_to research_parcel_path(@parcel),
                    alert: "Debes desbloquear la propiedad y aceptar el disclaimer para descargar el PDF."
        return
      end

      # ── Generación síncrona del PDF ──────────────────────────────
      pdf = ReportPdfBuilder.build(report_type: "ficha_snapshot", parcel: @parcel)

      filename = "TaxDeedLion_#{@parcel.parcel_id}_#{Date.today.strftime('%Y%m%d')}.pdf"
                 .gsub(/[^a-zA-Z0-9_\-.]/, "_")

      send_data pdf.render,
                filename:    filename,
                type:        "application/pdf",
                disposition: "attachment"
    end

    # GET /research/parcels/county_overview.json
    # Phase 1: Geographic Overview — aggregated county-level data for map pins
    def county_overview
      auctions = Auction.active_visible.includes(:parcels)

      grouped = auctions.group_by { |a| [a.county, a.state] }

      results = grouped.filter_map do |(county, state), auction_list|
        parcel_count  = auction_list.sum { |a| a.parcel_count || 0 }
        total_amount  = auction_list.sum { |a| a.total_amount.to_f }
        auction_count = auction_list.size

        lat, lng = nil, nil
        auction_with_coords = auction_list.find { |a| a.latitude.present? && a.longitude.present? }
        if auction_with_coords
          lat = auction_with_coords.latitude.to_f
          lng = auction_with_coords.longitude.to_f
        else
          auction_ids = auction_list.map(&:id)
          coords = Parcel.where(auction_id: auction_ids).has_coords
                         .pluck(:latitude, :longitude)
          if coords.any?
            lat = coords.sum { |c| c[0].to_f } / coords.size
            lng = coords.sum { |c| c[1].to_f } / coords.size
          end
        end

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
    # ══════════════════════════════════════════════════════════════════════
    # TWO-PHASE ENFORCEMENT: Solo acepta auction_id O county+state.
    # El modo state-only ha sido ELIMINADO — retorna 400 Bad Request.
    # ══════════════════════════════════════════════════════════════════════
    def map_data
      if params[:auction_id].present?
        auction = Auction.find_by(id: params[:auction_id])
        unless auction
          render json: { error: "Auction not found" }, status: :not_found and return
        end
        parcels = Parcel.for_auction(auction.id).has_coords

      elsif params[:county].present? && params[:state].present?
        # ✅ Fase 2: County drill-down — único modo permitido sin auction_id
        auction_ids = Auction.active_visible.by_state(params[:state])
                             .by_county(params[:county]).pluck(:id)
        parcels = Parcel.where(auction_id: auction_ids).has_coords

      else
        # ❌ Cualquier otro modo (incluyendo state-only) está PROHIBIDO
        render json: { error: "county+state or auction_id is required" }, status: :bad_request and return
      end

      # Apply the same inline filters as the list (min_bid, max_bid, property_type, q)
      parcels = apply_parcel_filters(parcels)

      parcels = parcels.select(
        :id, :address, :city, :county, :state, :zip_code,
        :parcel_id, :opening_bid, :latitude, :longitude,
        :property_type, :land_use, :zoning
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
          property_type: p.property_type.presence || p.land_use.presence || p.zoning.presence,
          lat:           p.latitude.to_f,
          lng:           p.longitude.to_f
        }
      }
    end

    # GET /research/parcels/parcels_list.json
    # ══════════════════════════════════════════════════════════════════════
    # TWO-PHASE ENFORCEMENT: Solo acepta auction_id O county+state.
    # El modo state-only ha sido ELIMINADO — retorna JSON vacío (no error).
    # ══════════════════════════════════════════════════════════════════════
    def parcels_list
      per_page = PER_PAGE_OPTIONS.include?(params[:per_page].to_i) ? params[:per_page].to_i : 25

      if params[:auction_id].present?
        auction = Auction.find_by(id: params[:auction_id])
        scope = auction ? Parcel.for_auction(auction.id) : Parcel.none

      elsif params[:county].present? && params[:state].present?
        # ✅ Fase 2: County drill-down — único modo permitido sin auction_id
        auction_ids = Auction.active_visible.by_state(params[:state])
                             .by_county(params[:county]).pluck(:id)
        scope = Parcel.where(auction_id: auction_ids)

      else
        # ❌ Sin contexto válido (incluyendo state-only): devuelve vacío
        render json: { parcels: [], meta: { total: 0, page: 1, pages: 0 } } and return
      end

      scope = apply_parcel_filters(scope)
      paginated = scope.includes(:auction).order(created_at: :desc).page(params[:page]).per(per_page)

      # Build a Set of parcel IDs this user has already unlocked — O(1) lookup, no N+1
      unlocked_ids = current_user.admin? ?
        Set.new(paginated.map(&:id)) :   # Admins see everything
        Set.new(
          ViewedParcel.where(user: current_user, parcel_id: paginated.map(&:id)).pluck(:parcel_id)
        )

      render json: {
        parcels: paginated.map { |p|
          # ── Property Type: cascada de campos hasta encontrar datos reales ──
          # Prioridad: property_type → land_use → zoning → '—'
          type_display = p.property_type.presence ||
                         p.land_use.presence ||
                         p.zoning.presence

          unlocked = unlocked_ids.include?(p.id)

          # ── Sensitive fields: truncate for locked parcels ─────────────────
          # Address: show first word (street number) blurred — city stays visible
          address_val  = p.address || '—'
          parcel_val   = p.parcel_id || '—'
          zip_val      = p.zip_code || '—'

          {
            id:                p.id,
            unlocked:          unlocked,
            # Send real values always — JS applies blur visually.
            # The backend also marks them so the client knows what to render.
            address:           address_val,
            city:              p.city,
            county:            p.county,
            state:             p.state,
            zip:               zip_val,
            parcel_id:         parcel_val,
            opening_bid:       p.opening_bid&.to_f,
            assessed_value:    p.assessed_value&.to_f,
            max_bid_30:        p.max_bid_30&.to_f,
            delinquent_amount: p.delinquent_amount&.to_f,
            property_type:     type_display,
            sale_date:         p.auction&.sale_date&.strftime("%b %d, %Y"),
            has_coords:        p.has_coords?,
            show_path:         "/research/parcels/#{p.id}"
          }
        },
        meta: {
          total:    paginated.total_count,
          page:     paginated.current_page,
          pages:    paginated.total_pages,
          per_page: per_page,
          from:     [paginated.offset_value + 1, paginated.total_count].min,
          to:       [paginated.offset_value + paginated.length, paginated.total_count].min
        }
      }
    end

    private

    def apply_parcel_filters(scope)
      scope = scope.search_text(params[:q])        if params[:q].present?
      # NOTE: by_county is NOT applied here — parcels are already scoped
      # via auction_ids for the selected county in parcels_list/map_data.
      # Applying it again is redundant and risks mismatches.
      scope = scope.by_state(params[:filter_state]) if params[:filter_state].present?
      scope = scope.min_bid(params[:min_bid])       if params[:min_bid].present?
      scope = scope.max_bid(params[:max_bid])       if params[:max_bid].present?
      if params[:property_type].present?
        pt = params[:property_type]
        scope = scope.where("land_use ILIKE :pt OR property_type ILIKE :pt", pt: "%#{pt}%")
      end
      scope
    end
  end
end