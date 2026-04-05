# frozen_string_literal: true

# SyncLog — registra cada ejecución del SyncSheetJob.
#
# status:
#   'running'  — job encolado / en progreso
#   'success'  — completado sin errores críticos
#   'failed'   — error fatal (no pudo conectar con Google Sheets, etc.)
#
class SyncLog < ApplicationRecord
  validates :status, inclusion: { in: %w[running success failed] }

  scope :recent,    -> { order(started_at: :desc) }
  scope :completed, -> { where(status: %w[success failed]) }
  scope :running,   -> { where(status: "running") }

  def duration_display
    return "—" unless duration_seconds
    if duration_seconds < 60
      "#{duration_seconds.round(1)}s"
    else
      "#{(duration_seconds / 60).round(1)}min"
    end
  end

  def total_processed
    (parcels_added || 0) + (parcels_updated || 0)
  end
end
