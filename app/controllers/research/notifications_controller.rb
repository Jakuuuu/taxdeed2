# frozen_string_literal: true

module Research
  # Inbox in-app del usuario. Alimenta el badge campanita del header
  # y el panel desplegable. La sección "Próximas subastas" del Portfolio
  # consulta directamente ParcelWatch (no Notification).
  class NotificationsController < BaseController
    before_action :require_active_subscription!

    # GET /research/notifications.json
    # Devuelve hasta 20 notificaciones recientes y el count de no leídas.
    def index
      scope = current_user.notifications.recent
      items = scope.limit(20).map { |n| serialize(n) }
      render json: {
        unread_count: current_user.notifications.unread.count,
        items: items
      }
    end

    # PATCH /research/notifications/:id/read
    def read
      notif = current_user.notifications.find(params[:id])
      notif.mark_read!
      render json: { ok: true, id: notif.id }
    end

    # POST /research/notifications/mark_all_read
    def mark_all_read
      current_user.notifications.unread.update_all(read_at: Time.current)
      render json: { ok: true }
    end

    private

    def serialize(n)
      parcel = n.notifiable_type == "Parcel" ? n.notifiable : nil
      {
        id: n.id,
        kind: n.kind,
        read: n.read?,
        created_at: n.created_at.iso8601,
        payload: n.payload,
        parcel_id: parcel&.id,
        parcel_url: parcel ? research_parcel_path(parcel) : nil
      }
    end
  end
end
