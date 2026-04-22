# frozen_string_literal: true

# Research::MarketStudy::CountiesController — Rama 4: Ficha de Condado
#
# Regla: 18-market-study.md
# Acceso: Requiere suscripción activa (heredado de Research::BaseController)
# Patrón: Drawer AJAX 95vw (show) + Grid de condados (index)
#
# ── Rutas ──────────────────────────────────────────────────────────────────
#   GET  /research/market_study/counties       → index (grid de condados)
#   GET  /research/market_study/counties/:id   → show  (ficha en drawer AJAX)
#
module Research
  module MarketStudy
    class CountiesController < Research::BaseController
      before_action :authenticate_user!
      before_action :set_county, only: [:show]

      # ── INDEX — Grid de Condados con Subastas ─────────────────────────────
      def index
        @counties = CountyMarketStat
          .with_active_auctions
          .order(:state, :county)

        # Búsqueda de texto (opcional)
        if params[:q].present?
          @counties = @counties.search_text(params[:q])
        end

        # Filtro por estado (opcional)
        if params[:state].present?
          @counties = @counties.by_state(params[:state])
        end

        # Estados disponibles para el filtro
        @available_states = CountyMarketStat.with_active_auctions
                                            .distinct
                                            .pluck(:state)
                                            .sort

        # Pre-calcular conteo de PROPIEDADES en subasta por condado (evita N+1)
        # Clave: [state.upcase, county.upcase] → count de parcels
        @auction_counts_by_county = Parcel
          .joins(:auction)
          .group("auctions.state", "auctions.county")
          .count
          .each_with_object({}) do |((state, county_name), count), hash|
            hash[[state.to_s.upcase, county_name.to_s.upcase]] = count
          end
      end

      # ── SHOW — Ficha Completa del Condado ─────────────────────────────────
      # XHR: Renderiza sin layout (drawer AJAX 95vw)
      # Direct URL: Renderiza con layout research (fallback seguro)
      def show
        @volumes = @county.real_estate_monthly_volumes.for_chart
        @active_auctions = Auction.where(state: @county.state, county: @county.county)
                                  .includes(:parcels)
        @total_properties = @active_auctions.sum { |a| a.parcels.size }

        render layout: false if request.xhr?
      end

      private

      def set_county
        @county = CountyMarketStat.find(params[:id])
      end
    end
  end
end
