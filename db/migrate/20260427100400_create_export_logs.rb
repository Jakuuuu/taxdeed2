# frozen_string_literal: true

class CreateExportLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :export_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.integer    :parcels_exported,            null: false
      t.string     :export_format, limit: 10, null: false, default: "csv"
      t.datetime   :exported_at, null: false, default: -> { "CURRENT_TIMESTAMP" }

      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :export_logs, [:user_id, :exported_at], name: "idx_export_logs_user_exported"
  end
end
