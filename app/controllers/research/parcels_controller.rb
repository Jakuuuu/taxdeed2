# frozen_string_literal: true

module Research
  class ParcelsController < BaseController
    PER_PAGE_OPTIONS = [25, 50, 100].freeze

    # GET /research/parcels
    def index
      @auctions_by_state = Auction.visible
                                  .order(state: :asc, sale_date: :asc)
                                  .group_by(&:state)
      @per_page = PER_PAGE_OPTIONS.include?(params[:per_page].to_i) ? params[:per_page].to_i : 25

      if params[:auction_id].present?
        @auction = Auction.find_by(id: params[:auction_id])
        scope    = Parcel.for_auction(@auction&.id)
        scope    = apply_parcel_filters(scope)
        @parcels = scope.order(created_at: :desc).page(params[:page]).per(@per_page)
      else
        @parcels = Parcel.none.page(1).per(25)
        @auction = nil
      end
    end

    # GET /research/parcels/:id
    def show
      @parcel  = Parcel.includes(:auction, :parcel_liens).find(params[:id])

      # ── Límite de vistas de parcelas ─────────────────────────────
      subscription = current_user.subscription
      already_seen = ViewedParcel.exists?(user_id: current_user.id, parcel_id: @parcel.id)

      unless already_seen
        if subscription.can_use?(:parcels)
          subscription.increment_usage!(:parcels)
          ViewedParcel.create!(user: current_user, parcel: @parcel)
        else
          redirect_to research_parcels_path,
            alert: "parcel_limit_reached" and return
        end
      end

      # ── Datos para la Ficha de Propiedad (3 columnas) ────────────
      @reports  = Report.for_parcel(@parcel.id).where(user: current_user).latest_first
      @crm_tag  = ParcelUserTag.find_by(user: current_user, parcel: @parcel)
      @crm_notes = ParcelUserNote.for_user_parcel(current_user, @parcel)
      @api_key  = ENV["GOOGLE_MAPS_API_KEY"]
      render layout: false if request.xhr?
    end

    # GET /research/parcels/map_data.json
    # Devuelve GeoJSON reducido para el mapa GIS de parcelas.
    # REQUIERE auction_id — nunca expone parcelas sin contexto de subasta.
    def map_data
      unless params[:auction_id].present?
        render json: { error: "auction_id is required" }, status: :bad_request and return
      end

      @auction = Auction.find_by(id: params[:auction_id])
      unless @auction
        render json: { error: "Auction not found" }, status: :not_found and return
      end

      parcels = Parcel.for_auction(@auction.id)
                      .has_coords
                      .select(:id, :address, :city, :county, :state, :zip,
                              :parcel_id, :opening_bid, :latitude, :longitude,
                              :property_type, :land_use)

      render json: parcels.map { |p|
        {
          id:            p.id,
          address:       p.address,
          city:          p.city,
          county:        p.county,
          state:         p.state,
          zip:           p.zip,
          parcel_id:     p.parcel_id,
          opening_bid:   p.opening_bid&.to_f,
          property_type: p.property_type,
          land_use:      p.land_use,
          lat:           p.latitude.to_f,
          lng:           p.longitude.to_f
        }
      }
    end

    # POST /research/parcels/:id/tag
    # Mini CRM — Rama 2 escribe exclusivamente
    def tag
      @parcel = Parcel.find(params[:id])
      tag_value = params[:tag].to_s.strip

      if tag_value.blank?
        # Sin valor → eliminar tag existente (reset)
        ParcelUserTag.where(user: current_user, parcel: @parcel).destroy_all
        render json: { tag: nil, label: nil, color: nil }
      elsif ParcelUserTag::VALID_TAGS.include?(tag_value)
        record = ParcelUserTag.upsert_for!(user: current_user, parcel: @parcel, tag: tag_value)
        render json: { tag: record.tag, label: record.label, color: record.color }
      else
        render json: { error: "Invalid tag" }, status: :unprocessable_entity
      end
    end

    # POST /research/parcels/:id/notes
    # Mini CRM — Rama 2 escribe exclusivamente
    def notes
      @parcel = Parcel.find(params[:id])
      body    = params[:body].to_s.strip

      if body.blank?
        render json: { error: "Note body cannot be empty" }, status: :unprocessable_entity
        return
      end

      note = ParcelUserNote.create!(
        user:   current_user,
        parcel: @parcel,
        body:   body
      )

      render json: {
        id:         note.id,
        body:       note.body,
        created_at: note.created_at.strftime("%b %d, %Y %H:%M")
      }
    end

    private

    def apply_parcel_filters(scope)
      scope = scope.search_text(params[:q])    if params[:q].present?
      scope = scope.by_county(params[:county]) if params[:county].present?
      scope = scope.min_bid(params[:min_bid])  if params[:min_bid].present?
      scope = scope.max_bid(params[:max_bid])  if params[:max_bid].present?
      scope = scope.where(property_type: params[:property_type]) if params[:property_type].present?
      scope
    end
  end
end