# frozen_string_literal: true

# SyncLog — registra cada ejecución del SyncSheetJob.
#
# status:
#   'running'  — job encolado / en progreso
#   'success'  — completado sin errores críticos
#   'failed'   — error fatal (no pudo conectar con Google Sheets, etc.)
#
class SyncLog < ApplicationRecord
  STATUSES = %w[running success failed].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :recent,    -> { order(started_at: :desc) }
  scope :completed, -> { where(status: %w[success failed]) }
  scope :running,   -> { where(status: "running") }
  scope :successful, -> { where(status: "success") }

  def duration_display
    return "—" unless duration_seconds
    if duration_seconds < 60
      "#{duration_seconds.round(1)}s"
    else
      mins = (duration_seconds / 60).floor
      secs = (duration_seconds % 60).round
      "#{mins}m #{secs}s"
    end
  end

  def total_processed
    (parcels_added || 0) + (parcels_updated || 0)
  end

  def success_rate_display
    total = total_processed + (parcels_skipped || 0)
    return "—" if total.zero?
    pct = ((total_processed.to_f / total) * 100).round(1)
    "#{pct}%"
  end

  def running?
    status == "running"
  end

  def success?
    status == "success"
  end

  def failed?
    status == "failed"
  end
end
