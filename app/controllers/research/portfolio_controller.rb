# frozen_string_literal: true

module Research
  class PortfolioController < BaseController
    # GET /research/portfolio
    # ══════════════════════════════════════════════════════════════════════
    # Rama 5: My Portfolio — Pipeline Kanban CRM
    #
    # Loads the pipeline board with all stages and their properties.
    # Auto-seeds default stages on first access.
    #
    # Queries:
    #   Q1: PipelineStage.ordered + eager-load pipeline_properties → parcel → auction
    #   Q2: ParcelUserTag  → tags_by_parcel Hash (for mini-card CRM chip)
    #   Q3: ParcelUserNote → latest note per parcel (for inline display)
    # ══════════════════════════════════════════════════════════════════════
    def show
      # Auto-seed pipeline stages on first access
      PipelineStage.seed_for!(current_user)

      # Q1 — Stages with eager-loaded properties and parcels
      @stages = current_user.pipeline_stages
                            .ordered
                            .includes(pipeline_properties: { parcel: :auction })

      # Q2 — CRM tags (for tag chip on mini-cards)
      @tags_by_parcel = current_user.parcel_user_tags.index_by(&:parcel_id)

      # Q3 — Latest note per parcel (for inline note display, truncated)
      @notes_by_parcel = current_user.parcel_user_notes
                                     .select("DISTINCT ON (parcel_id) parcel_id, body, created_at")
                                     .order(:parcel_id, created_at: :desc)
                                     .index_by(&:parcel_id)

      # KPI data
      all_props = @stages.flat_map(&:pipeline_properties)
      @kpi_total = all_props.size
      @kpi_total_bids = all_props.sum { |pp| pp.parcel.opening_bid.to_f }
      ready_stage = @stages.find { |s| s.crm_tag_map == "ready" }
      @kpi_ready = ready_stage ? ready_stage.pipeline_properties.size : 0

      # Próximas subastas — TODAS las cards del Pipeline con sale_date >= hoy.
      # Se cambió de parcel_watches a pipeline_properties (2026-05-03) para
      # cubrir al usuario que armó pipeline pero no activó el toggle 🔔.
      # Se incluye watch (LEFT JOIN) para mostrar el lead time si lo hay.
      @upcoming_pipeline = current_user.pipeline_properties
                                       .joins(parcel: :auction)
                                       .where("auctions.sale_date >= ?", Date.current)
                                       .includes(parcel: :auction)
                                       .order("auctions.sale_date ASC")
                                       .limit(20)

      # Lookup de watches por parcel_id para mostrar el lead time si existe.
      parcel_ids = @upcoming_pipeline.map(&:parcel_id)
      @watch_by_parcel = current_user.parcel_watches
                                     .where(parcel_id: parcel_ids)
                                     .index_by(&:parcel_id)
    end
  end
end
