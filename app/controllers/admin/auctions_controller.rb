# frozen_string_literal: true

# Admin::AuctionsController — CRUD completo para subastas (Tax Deed / Tax Lien)
#
# Flujo de estados:
#   upcoming → active → completed
#   (cambio manual por un admin via change_status)
#
class Admin::AuctionsController < Admin::BaseController
  before_action :set_auction, only: [:show, :edit, :update, :destroy, :change_status]

  # GET /admin/auctions
  def index
    scope = Auction.order(sale_date: :asc)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(state: params[:state])   if params[:state].present?

    @status_filter = params[:status]
    @state_filter  = params[:state]
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
    @auction = Auction.new
  end

  # POST /admin/auctions
  def create
    @auction = Auction.new(auction_params)
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
  def change_status
    new_status = params[:new_status]

    unless Auction::STATUSES.include?(new_status)
      return redirect_to admin_auction_path(@auction), alert: "Invalid status."
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

  def auction_params
    params.require(:auction).permit(
      :name, :county, :state, :sale_date, :registration_deadline,
      :status, :auction_type, :description, :website_url
    )
  end
end
