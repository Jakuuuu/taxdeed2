# frozen_string_literal: true

# ParcelWatch — el usuario quiere recibir un recordatorio antes de la sale_date
# de la subasta asociada a esta parcel.
#
# CRM Immunity: SyncSheetJob, GeocodeParcelsBatchJob y demás jobs de ingesta
# NUNCA tocan esta tabla (regla 13-jobs-and-sync.md).
class ParcelWatch < ApplicationRecord
  ALLOWED_DAYS = [1, 3, 7, 14, 30].freeze

  belongs_to :user
  belongs_to :parcel

  validates :user_id, uniqueness: { scope: :parcel_id }
  validates :notify_days_before,
    inclusion: { in: ALLOWED_DAYS, message: "must be one of #{ALLOWED_DAYS.join(', ')}" }

  scope :due_for_alert, -> {
    joins(parcel: :auction)
      .where("auctions.sale_date IS NOT NULL")
      .where("auctions.sale_date >= ?", Date.current)
      .where("auctions.sale_date - parcel_watches.notify_days_before <= ?", Date.current)
      .where("parcel_watches.last_notified_at IS NULL OR " \
             "parcel_watches.last_notified_at < " \
             "(auctions.sale_date - parcel_watches.notify_days_before)")
  }
end
