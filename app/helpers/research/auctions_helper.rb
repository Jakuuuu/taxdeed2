# frozen_string_literal: true

module Research
  module AuctionsHelper
    # Returns CSS class for SVG choropleth heatmap coloring based on auction count.
    def state_heat_class(state_name, auctions_by_state)
      data = auctions_by_state[state_name]
      return "no-auction" unless data
      count = data[:count] || 0
      case count
      when 0       then "no-auction"
      when 1..5    then "auction-low"
      when 6..20   then "auction-med"
      else              "auction-high"
      end
    end

    # Preserves current filter params across pagination links.
    # Strips Rails-internal keys and page (since we re-set it).
    def r1_pagination_params
      params.permit(:sub_tab, :status, :from_date, :to_date, :sort, :dir, :county, states: [])
            .to_h
            .symbolize_keys
    end

    # Generates a compact page range with ellipsis gaps for large page counts.
    # Example: [1, 2, :gap, 10, 11, 12, :gap, 25] for page 11 of 25.
    def r1_page_range(current, total)
      return (1..total).to_a if total <= 7

      pages = []
      # Always show first 2
      pages << 1
      pages << 2 if total >= 2

      # Window around current page
      window_start = [current - 1, 3].max
      window_end   = [current + 1, total - 2].min

      pages << :gap if window_start > 3
      (window_start..window_end).each { |p| pages << p }
      pages << :gap if window_end < total - 2

      # Always show last 2
      pages << (total - 1) if total >= 2
      pages << total

      pages.uniq
    end

    # ═══════════════════════════════════════════════════════════════════════
    # DRY — Shared county-grouped auction data builder.
    # Used by BOTH the US Overview (Rama 1) table AND the "Seleccionar
    # condado" picker in the Search module (Rama 2).
    #
    # Returns: { "FL" => [ { county:, state:, parcel_count:, total_amount:,
    #            sale_dates:, auction_ids:, bidding_url: }, ... ], ... }
    #
    # Each entry is ONE county row (multiple auction events consolidated).
    # ═══════════════════════════════════════════════════════════════════════
    def counties_with_auctions_grouped(auctions_scope = Auction.visible)
      all = auctions_scope.order(state: :asc, county: :asc)
      grouped_by_state = {}

      all.group_by(&:state).each do |state, state_auctions|
        by_county = state_auctions.group_by(&:county)
        grouped_by_state[state] = by_county.map do |county, auctions|
          {
            county:       county,
            state:        state,
            auction_ids:  auctions.map(&:id),
            parcel_count: auctions.sum { |a| a.parcel_count || 0 },
            total_amount: auctions.sum { |a| a.total_amount&.to_f || 0 },
            sale_dates:   auctions.filter_map(&:sale_date).sort,
            bidding_url:  auctions.find { |a| a.bidding_url.present? }&.bidding_url
          }
        end.sort_by { |c| c[:county] || "" }
      end

      grouped_by_state
    end
  end
end
