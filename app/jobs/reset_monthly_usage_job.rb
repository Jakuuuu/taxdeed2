# frozen_string_literal: true

# ResetMonthlyUsageJob — Reseteo mensual de contadores de uso
#
# Ejecutado diariamente a las 00:00 UTC por sidekiq-cron.
# Por cada Subscription activa cuyo current_period_end ya pasó,
# resetea los contadores de uso (used_parcels, used_avm, used_scope,
# title_search_used) y avanza current_period_end un mes hacia adelante.
#
# IMPORTANTE: Independiente de Stripe. Mientras MOCK_MODE esté activo o
# los webhooks de invoice.payment_succeeded no lleguen, este job es la
# única vía para que los créditos mensuales se renueven.
#
# SEGURIDAD:
#   - Skip status != "active" (trial / canceled / past_due no resetean)
#   - Skip current_period_end nil
#   - Avanza current_period_end por 1.month (alineado con PIVOT-03)
class ResetMonthlyUsageJob < ApplicationJob
  queue_as :default

  def perform
    now = Time.current
    due = Subscription.where(status: "active")
                      .where.not(current_period_end: nil)
                      .where("current_period_end <= ?", now)

    reset_count = 0
    due.find_each do |sub|
      Subscription.transaction do
        sub.lock!
        sub.update!(
          used_parcels:         0,
          used_avm:             0,
          used_scope:           0,
          title_search_used:    false,
          current_period_start: sub.current_period_end,
          current_period_end:   sub.current_period_end + 1.month
        )
      end
      reset_count += 1
    rescue StandardError => e
      Rails.logger.error "[ResetMonthlyUsageJob] Subscription ##{sub.id} failed: #{e.class}: #{e.message}"
    end

    Rails.logger.info "[ResetMonthlyUsageJob] ✅ #{reset_count} suscripción(es) reseteada(s) (period_end <= #{now.iso8601})"
  end
end
