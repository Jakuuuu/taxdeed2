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
  end
end
