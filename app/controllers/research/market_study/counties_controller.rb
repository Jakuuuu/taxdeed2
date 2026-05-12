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
# ── BUG FIX (2026-05-12) ── ALINEACIÓN DE CONTADORES CON RAMA 2 ────────────
#   PROBLEMA: @auction_counts_by_county (index) y @total_properties (show)
#   contaban parcels de TODAS las subastas históricas del condado (sin filtro
#   de fecha/estado). Pero el botón "Ver propiedades" navega a Rama 2
#   (ParcelsController), que aplica Auction.active_visible:
#     → scope :active_visible, -> { visible.time_active }
#     → visible      = status IN ('upcoming','active')
#     → time_active  = sale_date >= Date.current
#   Resultado: la card mostraba 10 propiedades, pero al hacer clic solo
#   aparecían 2 (las de subastas vigentes). Discrepancia engañosa para el
#   usuario y falsa señal de actividad en condados sin subastas activas.
#
#   SOLUCIÓN: Ambos contadores ahora usan Auction.active_visible como
#   fuente de verdad — el número mostrado siempre coincide con los
#   resultados que Rama 2 desplegará al hacer clic en el botón.
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
        # ✅ BUG FIX (2026-05-12): Aplicar Auction.active_visible para alinear con Rama 2.
        # El botón "Ver propiedades" en la ficha navega a ParcelsController que usa
        # active_visible (sale_date >= hoy AND status IN upcoming/active). Sin este filtro
        # el contador mostraba subastas pasadas/completadas → número engañoso.
        active_auction_ids = Auction.active_visible.pluck(:id)
        @auction_counts_by_county = Parcel
          .joins(:auction)
          .where(auction_id: active_auction_ids)
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
        # Calificadas explícitamente con auctions.state / auctions.county.
        #
        # ✅ BUG FIX (2026-05-12): Aplicar Auction.active_visible para alinear con Rama 2.
        # @total_properties alimenta el badge del botón "Ver propiedades (N)".
        # ParcelsController filtra por active_visible al recibir county+state:
        #   auction_ids = Auction.active_visible.by_state(...).by_county(...).pluck(:id)
        # Sin este filtro el badge mostraba el total histórico (todas las subastas
        # del condado) pero Rama 2 solo renderizaba las subastas vigentes → mismatch.
        active_county_auction_ids = Auction.active_visible
                                           .where(
                                             "LOWER(auctions.state) = ? AND LOWER(auctions.county) = ?",
                                             @county.state.to_s.downcase,
                                             @county.county.to_s.downcase
                                           )
                                           .pluck(:id)
        @total_properties = Parcel.where(auction_id: active_county_auction_ids).count
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
