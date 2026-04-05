# frozen_string_literal: true

# Admin::SyncController — Dashboard de monitoreo de sincronización Google Sheets.
#
# Permite:
#   - Ver historial de syncs (último primero)
#   - Disparar manualmente SyncSheetJob desde el panel
#
class Admin::SyncController < Admin::BaseController
  # GET /admin/sync
  def show
    @last_sync   = SyncLog.order(started_at: :desc).first
    @sync_history = SyncLog.order(started_at: :desc).limit(20)
  end

  # POST /admin/sync/run_now
  def run_now
    # Crear log de inicio inmediatamente
    sync_log = SyncLog.create!(
      status:     "running",
      started_at: Time.current
    )

    # Encolar el job, pasándole el sync_log_id para que lo actualice
    SyncSheetJob.perform_later(nil, sync_log.id)

    redirect_to admin_sync_path,
                notice: "Sync job enqueued. It will run in the background and update this dashboard."
  end
end
