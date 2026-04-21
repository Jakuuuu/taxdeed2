# frozen_string_literal: true

# RealEstateMonthlyVolume — Serie temporal de volumen inmobiliario (Rama 4)
#
# Fuente: Pestaña "Mercados" del Google Sheet
# Cada registro = volumen de dinero movido en un condado en un mes dado
# Anti-duplicados: UNIQUE INDEX en (county_market_stat_id, period_date)
# Tipo financiero: decimal(15,2) — NUNCA float
#
class RealEstateMonthlyVolume < ApplicationRecord
  belongs_to :county_market_stat

  # ── Validaciones ─────────────────────────────────────────────────────────
  validates :period_date, :volume_amount, presence: true
  validates :period_date, uniqueness: { scope: :county_market_stat_id }
  validates :volume_amount, numericality: { greater_than_or_equal_to: 0 }

  # ── Scopes ───────────────────────────────────────────────────────────────
  # Para el chart: ordenado cronológicamente
  scope :for_chart, -> { order(period_date: :asc) }

  # Filtrar desde un año específico
  scope :since, ->(year) { where("period_date >= ?", Date.new(year, 1, 1)) }

  # Últimos N meses
  scope :recent, ->(months = 24) {
    where("period_date >= ?", Date.current.beginning_of_month - months.months)
      .order(period_date: :asc)
  }

  # ── Helpers de formato ───────────────────────────────────────────────────
  def formatted_amount
    "$#{ActiveSupport::NumberHelper.number_to_delimited(volume_amount.to_i)}"
  end

  def period_label
    period_date.strftime("%b %Y")  # "Jan 2024"
  end

  def period_short_label
    period_date.strftime("%b '%y")  # "Jan '24"
  end
end
