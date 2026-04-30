# frozen_string_literal: true

module Research
  # Toggle de "Notificarme" en el Mini CRM (inmune a paywall).
  # Crear/actualizar/borrar un ParcelWatch NO consume créditos.
  class ParcelWatchesController < BaseController
    before_action :require_active_subscription!
    before_action :load_parcel

    # POST /research/parcels/:parcel_id/watch
    def create
      watch = current_user.parcel_watches.find_or_initialize_by(parcel: @parcel)
      watch.notify_days_before = clamp_days(params[:notify_days_before])
      watch.email_enabled      = ActiveModel::Type::Boolean.new.cast(params[:email_enabled])
      watch.in_app_enabled     = true

      if watch.save
        respond_with_state(watch)
      else
        render json: { error: watch.errors.full_messages.join(", ") },
               status: :unprocessable_entity
      end
    end

    # PATCH /research/parcels/:parcel_id/watch
    def update
      watch = current_user.parcel_watches.find_by!(parcel: @parcel)
      attrs = {}
      attrs[:notify_days_before] = clamp_days(params[:notify_days_before]) if params.key?(:notify_days_before)
      attrs[:email_enabled]      = ActiveModel::Type::Boolean.new.cast(params[:email_enabled]) if params.key?(:email_enabled)

      if watch.update(attrs)
        respond_with_state(watch)
      else
        render json: { error: watch.errors.full_messages.join(", ") },
               status: :unprocessable_entity
      end
    end

    # DELETE /research/parcels/:parcel_id/watch
    def destroy
      current_user.parcel_watches.where(parcel: @parcel).destroy_all
      respond_with_state(nil)
    end

    private

    def load_parcel
      @parcel = Parcel.find(params[:parcel_id])
    end

    def clamp_days(raw)
      n = raw.to_i
      ParcelWatch::ALLOWED_DAYS.include?(n) ? n : (current_user.default_notify_days_before || 7)
    end

    def respond_with_state(watch)
      render json: {
        watching: watch.present?,
        notify_days_before: watch&.notify_days_before,
        email_enabled: watch&.email_enabled || false
      }
    end
  end
end
