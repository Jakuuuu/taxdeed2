# frozen_string_literal: true

# AuctionTodayPipelineAlertsJob — Aviso del día de subasta para TODAS las
# cards del Pipeline (Rama 5), independientemente de si el usuario activó el
# toggle 🔔 del Mini CRM. La premisa: si una propiedad está en tu pipeline,
# asumimos que te importa.
#
# Cron sugerido: diario 11:00 UTC = 7:00 AM ET (sidekiq-cron).
# Idempotencia: Notification.exists? con created_at: today.all_day evita
# duplicados si el job corre dos veces el mismo día.
#
# CTA al Title Report (payload.report_cta):
#   'download' → existe Report (title_search, generated) para (user, parcel)
#   'generate' → ficha desbloqueada sin Title Report generated
#   nil        → ficha bloqueada → no empujamos al paywall el día D
class AuctionTodayPipelineAlertsJob < ApplicationJob
  queue_as :default

  def perform
    today   = Date.current
    created = 0

    PipelineProperty
      .joins(parcel: :auction)
      .where(auctions: { sale_date: today })
      .includes(:user, parcel: :auction)
      .find_each do |pp|
        next if already_notified_today?(pp, today)

        Notification.create!(
          user_id:          pp.user_id,
          notifiable_type:  "Parcel",
          notifiable_id:    pp.parcel_id,
          kind:             Notification::KIND_AUCTION_TODAY,
          delivery_channel: Notification::CHANNEL_IN_APP,
          payload:          build_payload(pp)
        )
        created += 1
      end

    Rails.logger.info "[AuctionTodayPipelineAlertsJob] ✅ #{created} notificaciones creadas"
  end

  private

  def already_notified_today?(pp, today)
    Notification.exists?(
      user_id:         pp.user_id,
      notifiable_type: "Parcel",
      notifiable_id:   pp.parcel_id,
      kind:            Notification::KIND_AUCTION_TODAY,
      created_at:      today.all_day
    )
  end

  def build_payload(pp)
    parcel  = pp.parcel
    auction = parcel.auction
    {
      title:            "Hoy se subasta tu propiedad",
      subtitle:         "#{parcel.county}, #{parcel.state} · #{auction.sale_date.strftime('%b %d, %Y')}",
      address:          parcel.address,
      county:           parcel.county,
      state:            parcel.state,
      sale_date:        auction.sale_date.iso8601,
      auto_archive_at:  (auction.sale_date + 7.days).iso8601,
      report_cta:       resolve_report_cta(pp.user_id, parcel.id)
    }
  end

  # 'download' | 'generate' | nil
  def resolve_report_cta(user_id, parcel_id)
    return "download" if Report.where(
      user_id:     user_id,
      parcel_id:   parcel_id,
      report_type: "title_search",
      status:      "generated"
    ).exists?

    ViewedParcel.unlocked?(user_id: user_id, parcel_id: parcel_id) ? "generate" : nil
  end
end
