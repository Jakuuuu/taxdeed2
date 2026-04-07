# frozen_string_literal: true

module Research
  class ParcelUserNotesController < BaseController
    before_action :require_active_subscription!

    # POST /research/parcel_user_notes?parcel_id=:id
    # Creates a new private note for the current user on a parcel.
    # Notes are append-only — users accumulate notes over time.
    def create
      @parcel = Parcel.find(params[:parcel_id])

      note = current_user.parcel_user_notes.new(
        parcel_id: @parcel.id,
        body: params[:body].to_s.strip
      )

      if note.body.blank?
        respond_to do |format|
          format.json { render json: { error: "Note cannot be blank" }, status: :unprocessable_entity }
          format.html { redirect_back fallback_location: research_parcel_path(@parcel), alert: "Note cannot be blank." }
        end
        return
      end

      note.save!

      respond_to do |format|
        format.json { render json: { note: { id: note.id, body: note.body, created_at: note.created_at } } }
        format.html { redirect_back fallback_location: research_parcel_path(@parcel), notice: "Note saved." }
      end
    end

    # DELETE /research/parcel_user_notes/:id
    # Allows the current user to delete their own note.
    def destroy
      note = current_user.parcel_user_notes.find(params[:id])
      note.destroy!

      respond_to do |format|
        format.json { render json: { deleted: true } }
        format.html { redirect_back fallback_location: request.referer || research_parcels_path }
      end
    end
  end
end
