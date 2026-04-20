# frozen_string_literal: true

# ExpireAuctionsJob — Higiene automática de subastas
#
# Ejecutado diariamente a las 6:00 UTC (2:00 AM ET) por sidekiq-cron.
# Marca como "completed" toda subasta cuya sale_date ya haya pasado
# y cuyo status siga siendo "upcoming" o "active".
#
# Esto mantiene la DB limpia y coherente con lo que la UI muestra
# a través del scope `active_visible` (que ya filtra por fecha).
#
# SEGURIDAD: Solo actualiza el campo `status`. No borra registros.
class ExpireAuctionsJob < ApplicationJob
  queue_as :default

  def perform
    expired_count = Auction
      .where(status: %w[upcoming active])
      .where("sale_date < ?", Date.current)
      .update_all(status: "completed")

    if expired_count > 0
      Rails.logger.info "[ExpireAuctionsJob] ✅ #{expired_count} subastas marcadas como completed (sale_date < #{Date.current})"
    else
      Rails.logger.info "[ExpireAuctionsJob] Sin subastas expiradas para actualizar."
    end
  end
end
