# frozen_string_literal: true

# Research::MarketStudy::CountiesController — Rama 4: Ficha de Condado
#
# Regla: 18-market-study.md
# Acceso: Requiere suscripción activa (heredado de Research::BaseController)
# Patrón: Página completa (show) + Grid de condados (index)
#
# ── Rutas ──────────────────────────────────────────────────────────────────
#   GET  /research/market_study/counties       → index (grid de condados)
#   GET  /research/market_study/counties/:id   → show  (ficha completa)
#
# ── QA Fixes (2026-05-11) ──────────────────────────────────────────────────
#   FIX-1: Eliminado includes(:parcels) + sum en Ruby → SQL GROUP BY + SUM
#   FIX-2: authenticate_user! redundante eliminado (ya garantizado por
#           BaseController#require_active_subscription! que llama authenticate_user!)
#   FIX-2v2: Corregido PG::AmbiguousColumn en show — columnas calificadas
#             con auctions.state / auctions.county (detectado en QA visual)
#   FIX-3: rescue RecordNotFound para evitar crash si el id no existe
#
module Research
  module MarketStudy
    class CountiesController < Research::BaseController
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
        # ✅ FIX-1: 1 sola query SQL. Clave: [state.upcase, county.upcase] → count de parcels
        @auction_counts_by_county = Parcel
          .joins(:auction)
          .group("auctions.state", "auctions.county")
          .count
          .each_with_object({}) do |((state, county_name), count), hash|
            hash[[state.to_s.upcase, county_name.to_s.upcase]] = count
          end
      end

      # ── SHOW — Ficha Completa del Condado ─────────────────────────────────
      # Página completa (NO drawer). render layout: false ha sido eliminado —
      # el comentario del docstring previo era incorrecto; Rama 4 usa página
      # completa según 18-market-study.md y market_study/views_and_routes.md.
      def show
        @volumes = @county.real_estate_monthly_volumes.for_chart

        # ✅ FIX-2 (v2): Corregido PG::AmbiguousColumn detectado en QA visual.
        # El problema: .merge(@active_auctions) propaga los scopes by_state/by_county
        # de Auction que emiten WHERE LOWER(state) = ? sin prefijo de tabla.
        # Al hacer JOIN parcels (que también tiene columnas state/county),
        # PostgreSQL no puede resolver la referencia → PG::AmbiguousColumn.
        #
        # Solución: calificar explícitamente con auctions.state / auctions.county
        # para que el planificador de consultas de PG nunca tenga ambigüedad.
        @total_properties = Parcel
          .joins(:auction)
          .where(
            "LOWER(auctions.state) = ? AND LOWER(auctions.county) = ?",
            @county.state.to_s.downcase,
            @county.county.to_s.downcase
          )
          .count
      end

      private

      def set_county
        # ✅ FIX-3: rescue RecordNotFound evita crash 500 si el id no existe.
        # Redirige al index con mensaje de error en lugar de romper el layout.
        @county = CountyMarketStat.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        redirect_to research_market_study_counties_path,
                    alert: "County not found."
      end
    end
  end
end
