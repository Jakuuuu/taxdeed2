# frozen_string_literal: true

# Admin::AuctionsController — CRUD completo para subastas (Tax Deed / Tax Lien)
#
# Flujo de estados (secuencial, unidireccional):
#   upcoming → active → completed
#   (cambio manual por un admin via change_status)
#
# Reglas:
#   - Status solo se cambia via `change_status` (no mass-assignable)
#   - Transición es secuencial: upcoming→active→completed (no se puede saltar ni retroceder)
#   - No se permite eliminar una subasta con parcelas asociadas
#
class Admin::AuctionsController < Admin::BaseController
  before_action :set_auction, only: [:show, :edit, :update, :destroy, :change_status]

  # Transiciones válidas — unidireccionales
  VALID_TRANSITIONS = { "upcoming" => "active", "active" => "completed" }.freeze

  # GET /admin/auctions
  def index
    scope = Auction.order(sale_date: :asc)

    # Búsqueda por texto (county o state)
    if params[:q].present?
      term = "%#{params[:q].strip}%"
      scope = scope.where("county ILIKE :q OR state ILIKE :q", q: term)
    end

    # Filtros
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(state: params[:state])   if params[:state].present?
    scope = scope.from_date(params[:from_date])   if params[:from_date].present?
    scope = scope.to_date(params[:to_date])       if params[:to_date].present?

    @search_query  = params[:q]
    @status_filter = params[:status]
    @state_filter  = params[:state]
    @from_date     = params[:from_date]
    @to_date       = params[:to_date]

    @counts = {
      all:       Auction.count,
      upcoming:  Auction.upcoming.count,
      active:    Auction.active.count,
      completed: Auction.completed.count
    }
    @states    = Auction.distinct.pluck(:state).compact.sort
    @auctions  = scope.page(params[:page]).per(30)
  end

  # GET /admin/auctions/:id
  def show
    @parcels = @auction.parcels.order(:parcel_id).page(params[:page]).per(50)
  end

  # GET /admin/auctions/new
  def new
    @auction = Auction.new(status: "upcoming")
  end

  # POST /admin/auctions
  def create
    @auction = Auction.new(auction_params)
    @auction.status = "upcoming" # Siempre inicia como upcoming
    if @auction.save
      redirect_to admin_auction_path(@auction), notice: "Auction created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /admin/auctions/:id/edit
  def edit; end

  # PATCH /admin/auctions/:id
  def update
    if @auction.update(auction_params)
      redirect_to admin_auction_path(@auction), notice: "Auction updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /admin/auctions/:id
  def destroy
    if @auction.parcels.exists?
      redirect_to admin_auction_path(@auction),
                  alert: "Cannot delete: auction has #{@auction.parcels.count} associated parcels."
    else
      @auction.destroy
      redirect_to admin_auctions_path, notice: "Auction deleted."
    end
  end

  # PATCH /admin/auctions/:id/change_status
  #
  # Enforce transición secuencial: upcoming → active → completed
  # No se permiten saltos ni retrocesos.
  def change_status
    new_status    = params[:new_status]
    expected_next = VALID_TRANSITIONS[@auction.status]

    unless expected_next == new_status
      return redirect_to admin_auction_path(@auction),
                         alert: "Invalid transition: '#{@auction.status}' → '#{new_status}'. " \
                                "Expected: '#{expected_next || 'none (already completed)'}'"
    end

    if @auction.update(status: new_status)
      redirect_to admin_auction_path(@auction),
                  notice: "Status changed to '#{new_status}'."
    else
      redirect_to admin_auction_path(@auction),
                  alert: "Could not change status."
    end
  end

  private

  def set_auction
    @auction = Auction.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_auctions_path, alert: "Auction not found."
  end

  # ⛔ `status` excluido intencionalmente — solo via `change_status`
  # ⛔ `name`, `description`, `website_url` NO existen en DB
  # Mapeo correcto: notes (no description), bidding_url (no website_url)
  def auction_params
    params.require(:auction).permit(
      :county, :state, :sale_date, :auction_type,
      :registration_deadline, :bidding_start, :registration_opens, :end_date,
      :bidding_url, :source_url, :notes,
      :latitude, :longitude, :parcel_count, :total_amount
    )
  end
end
