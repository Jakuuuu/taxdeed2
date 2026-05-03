# frozen_string_literal: true

# Notification — inbox in-app polimórfico.
#
# Se emite desde UpcomingAuctionAlertsJob (kind: auction_upcoming) y desde
# AuctionTodayPipelineAlertsJob (kind: auction_today). Se lee desde el badge
# campanita (header) y desde la sección "Próximas subastas" del Portfolio
# (Rama 5).
class Notification < ApplicationRecord
  KIND_AUCTION_UPCOMING = "auction_upcoming"
  KIND_AUCTION_TODAY    = "auction_today"
  CHANNEL_IN_APP = "in_app"
  CHANNEL_EMAIL  = "email"

  belongs_to :user
  belongs_to :notifiable, polymorphic: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def read?
    read_at.present?
  end

  def mark_read!
    update!(read_at: Time.current) unless read?
  end
end
