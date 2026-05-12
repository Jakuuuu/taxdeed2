# frozen_string_literal: true

module Research
  # ════════════════════════════════════════════════════════════════════════════
  # Rama 6 — Clear-to-Bid Catalog (Premier-only payload)
  # ════════════════════════════════════════════════════════════════════════════
  # Endpoint único: GET /research/clear_to_bid
  #
  # Política de fuga (CRÍTICA — auditada):
  #   - El controller SIEMPRE renderiza (no bloquea con 403/redirect a paywall),
  #     pero el payload servido cambia drásticamente según el tier:
  #
  #       Premier + active   → @parcels_full   (address, parcel_id, coords, opening_bid…)
  #       Cualquier otro     → @parcels_teaser (id, state, county, grade)
  #
  #   - El HTML servido a NO-Premier nunca debe contener datos sensibles.
  #     No se confía en CSS/JS para ocultar — el server jamás los emite.
  #
  #   - No existe endpoint member (`show?id=`). Toda la superficie es el
  #     catálogo agregado, lo que cierra el bypass por parcela individual.
  #
  #   - Params como `?force=1` se ignoran. Un `?parcel_id=` para no-Premier
  #     dispara redirect silencioso a paywall (no leak por error verbose).
  # ════════════════════════════════════════════════════════════════════════════
  class ClearToBidController < BaseController
    include ClearToBidPayload

    # Notas sobre guards:
    #   1. authenticate_user!         (heredado vía ApplicationController/Devise)
    #   2. require_active_subscription!  (heredado vía Research::BaseController)
    #
    # Importante: require_active_subscription! YA bloquea sin sub o canceled,
    # redirigiendo a subscription_required_path. Solo llegan a `show` usuarios
    # con status in (trial, active). La diferenciación Premier vs no-Premier
    # ocurre EN LA QUERY, no en un before_action que bloquee, porque la
    # pantalla es intencionalmente upsell-friendly.
    before_action :load_premier_status
    before_action :block_member_bypass_for_non_premier, only: :show

    PARCELS_PAGE_LIMIT = 50

    # GET /research/clear_to_bid
    def show
      if @premier_paid
        # PROYECCIÓN explícita también para Premier — solo cargamos las columnas
        # que el payload `clear_to_bid_full` realmente emite (evita N+1 implícito
        # sobre columnas pesadas como legal_description / technical_analysis).
        full_relation = Parcel.clear_to_bid
                              .select(
                                :id, :auction_id, :parcel_id, :state, :county, :address,
                                :latitude, :longitude, :polygon_encoded, :opening_bid,
                                :market_value, :year_built, :lot_area_acres, :property_type,
                                :clear_to_bid_grade, :internal_status, :updated_at
                              )
                              .includes(:auction)
                              .order(updated_at: :desc)
                              .limit(PARCELS_PAGE_LIMIT)
        @parcels_full   = clear_to_bid_full(full_relation)
        @parcels_teaser = nil
      else
        # PROYECCIÓN explícita: SELECT solo columnas no-sensibles.
        # Address, parcel_id externo, opening_bid, lat/lng NUNCA se cargan.
        teaser_relation = Parcel.clear_to_bid
                                .select(:id, :state, :county, :clear_to_bid_grade, :updated_at)
                                .order(updated_at: :desc)
                                .limit(PARCELS_PAGE_LIMIT)
        @parcels_teaser = clear_to_bid_skeleton(teaser_relation)
        @parcels_full   = nil

        log_upsell_view!
      end

      @upgrade_required = !@premier_paid
      @stats = compute_catalog_stats
    end

    private

    # Agregados públicos del catálogo (mismas cifras para Premier y non-Premier:
    # son los hooks de upsell del hero header — no exponen PII).
    # Cacheado 5 min: 4 queries SQL evitadas en cada render del catálogo.
    # Invalida solo por TTL — el lag aceptable porque el catálogo se actualiza
    # vía sync nocturno, no real-time.
    STATS_CACHE_KEY = "research:clear_to_bid:catalog_stats:v1"
    STATS_CACHE_TTL = 5.minutes

    def compute_catalog_stats
      Rails.cache.fetch(STATS_CACHE_KEY, expires_in: STATS_CACHE_TTL) do
        base = Parcel.clear_to_bid
        {
          total:        base.count,
          optimo:       base.where(clear_to_bid_grade: "optimo").count,
          avg_min_bid:  base.where.not(opening_bid: nil).average(:opening_bid)&.to_i,
          county_count: base.distinct.count(:county)
        }
      end
    end

    # Define @premier_paid para que la vista ramifique sin tocar la sesión de nuevo.
    # Admin override: los admins siempre reciben el payload completo (@parcels_full)
    # independientemente de su plan de suscripción. Esto les permite auditar y
    # previsualizar el catálogo Hot Deals sin necesidad de un plan Premier.
    # Ver: software/rules/hotdeals/nav_visibility.md
    def load_premier_status
      @premier_paid = current_user.admin? || current_user.subscription&.premier_active? || false
    end

    # Anti-bypass: si un no-Premier intenta `?parcel_id=...` para forzar un
    # preview directo de UNA parcela, redirigimos a paywall (silencioso).
    # Premier puede pasar parcel_id sin efecto: simplemente se ignora.
    def block_member_bypass_for_non_premier
      return if @premier_paid
      return if params[:parcel_id].blank?

      log_upsell_view!(reason: "member_bypass_attempt")
      redirect_to subscription_required_path,
        alert: "This feature is available on the Premier plan."
    end

    def log_upsell_view!(reason: "catalog_view")
      sub = current_user.subscription
      Rails.logger.info(
        "[CLEAR_TO_BID:UPSELL_VIEW] " \
        "user_id=#{current_user.id} " \
        "subscription_plan=#{sub&.plan_name || 'none'} " \
        "subscription_status=#{sub&.status || 'none'} " \
        "reason=#{reason}"
      )
    end
  end
end
