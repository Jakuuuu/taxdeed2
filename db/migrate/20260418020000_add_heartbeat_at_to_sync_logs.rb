# frozen_string_literal: true

# Agrega heartbeat_at a sync_logs para separar el heartbeat del timestamp de inicio.
#
# BUG RESUELTO: El heartbeat del SyncSheetJob actualizaba started_at,
# lo que enmascaraba la detección de zombies reales. Con este campo separado,
# el zombie detector puede usar MAX(started_at, heartbeat_at) para saber
# cuándo fue la última señal de vida, sin perder el timestamp original.
class AddHeartbeatAtToSyncLogs < ActiveRecord::Migration[7.2]
  def change
    add_column :sync_logs, :heartbeat_at, :datetime, null: true
  end
end
