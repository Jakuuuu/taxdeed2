# frozen_string_literal: true

module Research
  class AuctionsController < BaseController
    before_action :require_active_subscription!
    before_action :set_auction, only: [ :show ]

    PER_PAGE = 25

    # GET /research/auctions
    # GET /research/auctions.json
    def index
      # ── Base scope: apply filters from params ──────────────────────────────
      base_scope = apply_filters(Auction.all)

      # Sub-tab: "prior" shows only completed auctions
      if params[:sub_tab] == "prior"
        base_scope = base_scope.where(status: "completed")
      end

      # ── Sortable columns (whitelisted) ──────────────────────────────────
      sort_column = %w[county state sale_date parcel_count total_amount].include?(params[:sort]) ? params[:sort] : "sale_date"
      sort_dir    = params[:dir] == "desc" ? :desc : :asc
      @auctions_scope = base_scope.order(sort_column => sort_dir)

      # ── Server-side pagination ─────────────────────────────────────────────
      @page       = [ params[:page].to_i, 1 ].max
      @total_count = @auctions_scope.count
      @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
      @page        = [ @page, @total_pages ].min
      @auctions    = @auctions_scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

      # ── Map: all visible filtered auctions for the choropleth heatmap ───────
      # NOTE: We do NOT restrict by lat/lng here — Florida has 64 auctions with
      # no coordinates but they should still color the state on the choropleth.
      @choropleth_auctions = apply_filters(Auction.visible)

      # Subset with coordinates for potential point-marker overlays (future use)
      @map_auctions = @choropleth_auctions
                        .where.not(latitude: nil)
                        .where.not(longitude: nil)

      # ── Summary counts via SQL (no N+1 iteration in Ruby) ──────────────────
      @count_upcoming      = @auctions_scope.where(status: "upcoming").count
      @count_active        = @auctions_scope.where(status: "active").count
      @count_total         = @total_count
      @count_total_parcels = @auctions_scope.sum(:parcel_count)
      @total_amount        = @auctions_scope.sum(:total_amount)

      # ── State dropdown badges — count per state ────────────────────────────
      @states_with_counts = Auction.visible
                                   .group(:state)
                                   .count
                                   .sort_by { |state, _| state || "" }

      # ── Heatmap data: group visible auctions by state for the choropleth ───
      # DB stores abbreviations (FL, TX), but the SVG calls state_heat_class('Florida', …)
      # so we must re-key by full state name.
      state_abbr_to_name = {
        "AL" => "Alabama", "AK" => "Alaska", "AZ" => "Arizona", "AR" => "Arkansas",
        "CA" => "California", "CO" => "Colorado", "CT" => "Connecticut", "DE" => "Delaware",
        "FL" => "Florida", "GA" => "Georgia", "HI" => "Hawaii", "ID" => "Idaho",
        "IL" => "Illinois", "IN" => "Indiana", "IA" => "Iowa", "KS" => "Kansas",
        "KY" => "Kentucky", "LA" => "Louisiana", "ME" => "Maine", "MD" => "Maryland",
        "MA" => "Massachusetts", "MI" => "Michigan", "MN" => "Minnesota", "MS" => "Mississippi",
        "MO" => "Missouri", "MT" => "Montana", "NE" => "Nebraska", "NV" => "Nevada",
        "NH" => "New Hampshire", "NJ" => "New Jersey", "NM" => "New Mexico", "NY" => "New York",
        "NC" => "North Carolina", "ND" => "North Dakota", "OH" => "Ohio", "OK" => "Oklahoma",
        "OR" => "Oregon", "PA" => "Pennsylvania", "RI" => "Rhode Island", "SC" => "South Carolina",
        "SD" => "South Dakota", "TN" => "Tennessee", "TX" => "Texas", "UT" => "Utah",
        "VT" => "Vermont", "VA" => "Virginia", "WA" => "Washington", "WV" => "West Virginia",
        "WI" => "Wisconsin", "WY" => "Wyoming", "DC" => "District of Columbia"
      }

      @auctions_by_state = @choropleth_auctions.group_by(&:state).each_with_object({}) do |(abbr, aucts), h|
        full_name = state_abbr_to_name[abbr] || abbr
        h[full_name] = {
          count:         aucts.size,
          total_parcels: aucts.sum { |a| a.parcel_count || 0 },
          total_amount:  aucts.sum { |a| a.total_amount&.to_f || 0 },
          auctions:      aucts
        }
      end

      # ── Calendar events: group by sale_date for JS calendar ────────────────
      visible_for_cal = apply_filters(Auction.visible).where.not(sale_date: nil)
      @calendar_events = visible_for_cal.select(:id, :county, :state, :sale_date, :parcel_count, :status)
                                        .order(sale_date: :asc)
                                        .group_by { |a| a.sale_date.strftime("%Y-%m-%d") }
                                        .transform_values do |aucts|
                                          aucts.map { |a| { id: a.id, jurisdiction: "#{a.county}, #{a.state}", parcels: a.parcel_count || 0, status: a.status } }
                                        end

      respond_to do |format|
        format.html
        format.json do
          render json: @map_auctions.map { |a| auction_json(a) }
        end
      end
    end

    # GET /research/auctions/jurisdictions.json?states[]=Florida&states[]=Texas
    # AJAX endpoint for predictive State → Jurisdiction filtering
    def jurisdictions
      states = Array(params[:states]).compact.reject(&:blank?)
      if states.empty?
        render json: []
        return
      end

      jurisdictions = Auction.visible
                             .where(state: states)
                             .group(:county, :state)
                             .count
      render json: jurisdictions.map { |(county, state), count|
        { name: "#{county}, #{state}", count: count }
      }.sort_by { |j| j[:name] }
    end

    # GET /research/auctions/:id  — Página estadística pura de la subasta
    # ⚠️ RAMA 1: No consulta parcels individuales. No enlaza a Parcel#show.
    # Único CTA: "View Parcels →" → /research/parcels?auction_id=:id
    def show
      # Solo stats de la subasta (sin queries a parcels table)
      @timeline_steps = [
        { label: "Registration Opens",    date: @auction.registration_opens },
        { label: "Registration Deadline", date: @auction.registration_deadline },
        { label: "Bidding Start",         date: @auction.bidding_start },
        { label: "Sale Date",             date: @auction.sale_date },
        { label: "End Date",              date: @auction.end_date }
      ].reject { |s| s[:date].nil? }
    end

    private

    def set_auction
      @auction = Auction.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to research_auctions_path, alert: "Auction not found."
    end

    def apply_filters(scope)
      # Multi-state filtering: states[] array param
      if params[:states].present?
        scope = scope.where(state: Array(params[:states]).compact.reject(&:blank?))
      elsif params[:state].present?
        scope = scope.by_state(params[:state])
      end

      scope = scope.by_county(params[:county])     if params[:county].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.from_date(params[:from_date])  if params[:from_date].present?
      scope = scope.to_date(params[:to_date])      if params[:to_date].present?

      scope
    end

    def auction_json(auction)
      {
        id:              auction.id,
        jurisdiction:    auction.jurisdiction,
        state:           auction.state,
        county:          auction.county,
        auction_type:    "tax_deed",
        sale_date:       auction.sale_date&.strftime("%Y-%m-%d"),
        sale_date_label: auction.sale_date&.strftime("%b %d, %Y"),
        parcel_count:    auction.parcel_count || 0,
        total_amount:    auction.total_amount&.to_f || 0,
        status:          auction.status,
        latitude:        auction.latitude&.to_f,
        longitude:       auction.longitude&.to_f,
        bidding_url:     auction.bidding_url,
        parcels_url:     research_parcels_path(auction_id: auction.id)
        # ⚠️ show_url eliminado — Rama 1 no usa Parcel#show ni links internos de parcela
      }
    end
  end
end
