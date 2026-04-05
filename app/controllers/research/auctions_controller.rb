# frozen_string_literal: true

module Research
  class AuctionsController < BaseController
    before_action :require_active_subscription!
    before_action :set_auction, only: [ :show ]

    # GET /research/auctions
    # GET /research/auctions.json
    def index
      # Base scope: apply filters from params
      @auctions = apply_filters(Auction.all).order(sale_date: :asc)

      # Map: only visible (upcoming + active) with valid coordinates
      @map_auctions = @auctions.visible.where.not(latitude: nil).where.not(longitude: nil)

      # ── Summary counts via SQL (no N+1 iteration in Ruby) ───────────────────
      @count_upcoming      = @auctions.where(status: "upcoming").count
      @count_active        = @auctions.where(status: "active").count
      @count_total         = @auctions.count
      @count_total_parcels = @auctions.sum(:parcel_count)
      @total_amount        = @auctions.visible.sum(:total_amount)

      # ── Filter dropdowns ─────────────────────────────────────────────────────
      @states = Auction.distinct.pluck(:state).compact.sort
      @counties_by_state = Auction.all
                                  .pluck(:state, :county)
                                  .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(s, c), h|
                                    h[s] << c if c.present?
                                  end
                                  .transform_values(&:uniq).transform_values(&:sort)
      @all_counties = Auction.distinct.pluck(:county).compact.sort

      # ── Calendar views — group by date for daily/weekly/monthly tabs ─────────
      visible_auctions = @auctions.visible
      @calendar_daily   = visible_auctions.group_by { |a| a.sale_date }
                                          .sort_by { |date, _| date || Date.new(9999) }
      @calendar_weekly  = visible_auctions.group_by { |a| a.sale_date&.beginning_of_week }
                                          .sort_by { |date, _| date || Date.new(9999) }
      @calendar_monthly = visible_auctions.group_by { |a| a.sale_date&.beginning_of_month }
                                          .sort_by { |date, _| date || Date.new(9999) }

      # ── Heatmap data: group visible auctions by state for the choropleth ─────
      @auctions_by_state = @map_auctions.group_by(&:state).transform_values do |aucts|
        {
          count:        aucts.size,
          total_parcels: aucts.sum { |a| a.parcel_count || 0 },
          total_amount:  aucts.sum { |a| a.total_amount&.to_f || 0 },
          auctions:     aucts
        }
      end

      respond_to do |format|
        format.html
        format.json do
          render json: @map_auctions.map { |a| auction_json(a) }
        end
      end
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
      scope = scope.by_state(params[:state])       if params[:state].present?
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
