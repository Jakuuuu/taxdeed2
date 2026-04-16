# frozen_string_literal: true

# SyncLog — registra cada ejecución del SyncSheetJob.
#
# status:
#   'running'               — job encolado / en progreso
#   'success'               — completado sin errores críticos
#   'completed_with_errors' — sync terminó pero algunas filas fallaron
#   'failed'                — error fatal (no pudo conectar con Google Sheets, etc.)
#
# 🛡️ AUTO-HEAL (v2):
#   expire_zombies! detecta SyncLogs que llevan más de ZOMBIE_TIMEOUT en estado
#   "running" y los fuerza a "failed". Esto desbloquea el Guard Anti-Duplicados
#   y el botón "Run Sync Now" del dashboard admin.
#
class SyncLog < ApplicationRecord
  STATUSES = %w[running success completed_with_errors failed].freeze

  # ── ZOMBIE TIMEOUT ─────────────────────────────────────────────────────────
  # Un sync legítimo no debería tardar más de 15 minutos.
  # Si supera este umbral, el job está muerto y el log es un "zombie".
  ZOMBIE_TIMEOUT = 15.minutes

  validates :status, inclusion: { in: STATUSES }

  scope :recent,    -> { order(started_at: :desc) }
  scope :completed, -> { where(status: %w[success completed_with_errors failed]) }
  scope :running,   -> { where(status: "running") }
  scope :successful, -> { where(status: "success") }
  scope :zombies,   -> { running.where("started_at < ?", ZOMBIE_TIMEOUT.ago) }

  # ═══════════════════════════════════════════════════════════════════════════
  # 🧟 AUTO-HEAL: Detecta y elimina registros zombie
  #
  # Un zombie es un SyncLog con status "running" que lleva más de ZOMBIE_TIMEOUT
  # sin completarse. Causas comunes:
  #   - Sidekiq worker caído (Render free tier suspend)
  #   - Redis perdió el job encolado
  #   - Job crasheó fuera del rescue (SIGKILL, OOM)
  #   - Error no manejado antes del blindaje v2
  #
  # Se invoca automáticamente desde:
  #   - Admin::SyncController#show  (al cargar el dashboard)
  #   - Admin::SyncController#run_now (antes de encolar un nuevo job)
  #
  # Retorna: el número de zombies exterminados.
  # ═══════════════════════════════════════════════════════════════════════════
  def self.expire_zombies!
    zombified = zombies
    count = 0

    zombified.find_each do |log|
      elapsed_minutes = ((Time.current - log.started_at) / 60).round(0)
      log.update!(
        status:           "failed",
        error_message:    "Job Timeout - Zombie Process. Sync was stuck in 'running' for " \
                          "#{elapsed_minutes} minutes. The Sidekiq worker likely crashed or " \
                          "was killed (OOM/SIGKILL). Check Render dashboard → worker service.",
        duration_seconds: (Time.current - log.started_at).round(1),
        completed_at:     Time.current
      )
      count += 1
      Rails.logger.warn "[SyncLog] 🧟 Expired zombie SyncLog ##{log.id} (stuck for #{elapsed_minutes}min)"
    end

    count
  end

  # ── Display Helpers ──────────────────────────────────────────────────────────

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

  def completed_with_errors?
    status == "completed_with_errors"
  end

  def failed?
    status == "failed"
  end
end
