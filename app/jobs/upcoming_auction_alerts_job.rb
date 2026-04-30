# frozen_string_literal: true

# UpcomingAuctionAlertsJob — Genera notificaciones in-app cuando una parcela
# observada (ParcelWatch) entra en su ventana `notify_days_before` antes de
# la sale_date.
#
# Cron sugerido: diario 07:00 UTC (sidekiq-cron / config/schedule.yml).
# Idempotente: usa `last_notified_at` para no duplicar.
#
# Email (Fase 2): cuando email_enabled? && proveedor configurado, encolar
# AuctionReminderMailer.upcoming(watch).deliver_later — sin migración nueva.
class UpcomingAuctionAlertsJob < ApplicationJob
  queue_as :default

  def perform
    created = 0

    ParcelWatch.due_for_alert.find_each do |watch|
      parcel  = watch.parcel
      auction = parcel.auction
      next unless auction&.sale_date

      days_left = (auction.sale_date - Date.current).to_i

      Notification.create!(
        user_id:          watch.user_id,
        notifiable_type:  "Parcel",
        notifiable_id:    parcel.id,
        kind:             Notification::KIND_AUCTION_UPCOMING,
        delivery_channel: Notification::CHANNEL_IN_APP,
        payload: {
          title:    "Subasta en #{days_left} día#{'s' if days_left != 1}",
          subtitle: "#{parcel.county}, #{parcel.state} · #{auction.sale_date.strftime('%b %d, %Y')}",
          county:   parcel.county,
          state:    parcel.state,
          sale_date: auction.sale_date.iso8601,
          days_left: days_left
        }
      )

      watch.update_column(:last_notified_at, Time.current)
      created += 1

      # Fase 2 (email): activar cuando exista proveedor configurado.
      # if watch.email_enabled? && Rails.application.config.x.email_enabled
      #   AuctionReminderMailer.upcoming(watch).deliver_later
      # end
    end

    Rails.logger.info "[UpcomingAuctionAlertsJob] ✅ #{created} notificaciones creadas"
  end
end
