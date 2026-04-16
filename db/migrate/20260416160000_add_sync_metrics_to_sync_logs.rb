# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════════════
# FIX Bug #2: SyncSheetJob escribe records_synced y records_failed pero
# esas columnas no existían en sync_logs → ActiveModel::UnknownAttributeError
# tras cada sync exitoso, convirtiendo syncs exitosos en "failed".
# ═══════════════════════════════════════════════════════════════════════════════
class AddSyncMetricsToSyncLogs < ActiveRecord::Migration[7.2]
  def change
    add_column :sync_logs, :records_synced, :integer, default: 0, null: false
    add_column :sync_logs, :records_failed, :integer, default: 0, null: false
  end
end
