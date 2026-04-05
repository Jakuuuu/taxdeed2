# frozen_string_literal: true

# Registra el historial de sincronizaciones Google Sheets → PostgreSQL.
# Usado por el Sync Dashboard en el panel admin.
class CreateSyncLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :sync_logs do |t|
      t.string   :status,           null: false, default: "running"
        # 'running' | 'success' | 'failed'
      t.integer  :parcels_added,    default: 0
      t.integer  :parcels_updated,  default: 0
      t.integer  :parcels_skipped,  default: 0
      t.float    :duration_seconds
      t.text     :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps null: false
    end

    add_index :sync_logs, :status
    add_index :sync_logs, :started_at
  end
end
