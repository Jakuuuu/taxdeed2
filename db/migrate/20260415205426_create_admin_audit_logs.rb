# frozen_string_literal: true

class CreateAdminAuditLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :admin_audit_logs do |t|
      t.references :admin_user,  null: false, foreign_key: { to_table: :users }
      t.references :target_user, null: false, foreign_key: { to_table: :users }
      t.string :action,  null: false  # toggle_admin, reset_usage, cancel_subscription
      t.text   :details               # Human-readable description

      t.timestamps
    end

    add_index :admin_audit_logs, :action
    add_index :admin_audit_logs, :created_at
  end
end
