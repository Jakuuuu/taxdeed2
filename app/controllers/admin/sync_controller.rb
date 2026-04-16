# frozen_string_literal: true

# Admin::SyncController — Dashboard de monitoreo de sincronización Google Sheets.
#
# Permite:
#   - Ver historial de syncs (último primero)
#   - Disparar manualmente SyncSheetJob desde el panel
#
# ⛔ CRM IMMUNITY: Este controller NO altera la lógica del SyncSheetJob.
#   Solo lo encola y monitorea vía SyncLog. Las tablas parcel_user_tags
#   y parcel_user_notes permanecen absolutamente intocables.
#
class Admin::SyncController < Admin::BaseController
  # GET /admin/sync
  def show
    @last_sync    = SyncLog.recent.first
    @sync_history = SyncLog.recent.limit(20)
    @running      = SyncLog.running.exists?

    # Métricas agregadas para el dashboard
    @total_syncs     = SyncLog.count
    @successful      = SyncLog.where(status: "success").count
    @failed          = SyncLog.where(status: "failed").count
    @total_added     = SyncLog.sum(:parcels_added)
    @total_updated   = SyncLog.sum(:parcels_updated)
    @avg_duration    = SyncLog.where(status: "success")
                              .where.not(duration_seconds: nil)
                              .average(:duration_seconds)&.round(1)
  end

  # POST /admin/sync/run_now
  #
  # ⛔ Guard anti-duplicados ATÓMICO con Advisory Lock de PostgreSQL.
  # Previene TOCTOU race conditions: si 3 requests llegan en <50ms,
  # solo UNO adquiere el lock, crea el SyncLog y encola el job.
  # Los demás rebotan inmediatamente con un mensaje de alerta.
  #
  # Mecanismo: pg_try_advisory_lock(73827591) — ID numérico fijo.
  #   - El primero en llegar obtiene el lock → crea SyncLog + encola job → libera lock.
  #   - Los concurrentes reciben false → redirect con alerta (sin esperar).
  #   - Eliminación total de la ventana TOCTOU entre exists? y create!.
  #
  SYNC_ADVISORY_LOCK_ID = 73_827_591

  def run_now
    result = obtain_sync_lock_and_enqueue

    case result
    when :lock_contention
      redirect_to admin_sync_path,
                  alert: "A sync request is already being processed. Please wait."
    when :already_running
      redirect_to admin_sync_path,
                  alert: "A sync is already in progress. Please wait for it to finish."
    else
      # result is the SyncLog instance
      SyncSheetJob.perform_later(nil, result.id)
      redirect_to admin_sync_path,
                  notice: "Sync job enqueued. It will run in the background and update this dashboard."
    end
  end

  private

  # Adquiere advisory lock, verifica que no haya sync running, y crea el SyncLog.
  # Retorna:
  #   :lock_contention  — otro request ya tiene el lock (triple-clic simultáneo)
  #   :already_running   — ya existe un SyncLog con status 'running'
  #   SyncLog            — el log recién creado (éxito)
  def obtain_sync_lock_and_enqueue
    SyncLog.transaction do
      # pg_try_advisory_lock es no-bloqueante: retorna true/false inmediatamente.
      # El advisory lock es session-level — se libera explícitamente al final.
      locked = ActiveRecord::Base.connection.select_value(
        "SELECT pg_try_advisory_lock(#{SYNC_ADVISORY_LOCK_ID})"
      )

      unless locked
        next :lock_contention
      end

      if SyncLog.running.exists?
        ActiveRecord::Base.connection.execute(
          "SELECT pg_advisory_unlock(#{SYNC_ADVISORY_LOCK_ID})"
        )
        next :already_running
      end

      sync_log = SyncLog.create!(
        status:     "running",
        started_at: Time.current
      )

      ActiveRecord::Base.connection.execute(
        "SELECT pg_advisory_unlock(#{SYNC_ADVISORY_LOCK_ID})"
      )

      sync_log
    end
  end
end
