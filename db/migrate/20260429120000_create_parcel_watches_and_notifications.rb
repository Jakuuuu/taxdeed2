# frozen_string_literal: true

# Notificaciones de subasta para el CRM (Rama 5 + Mini CRM).
#   - parcel_watches: 1 fila por user×parcel a la que el usuario quiere
#     que se le avise antes de la sale_date.
#   - notifications: inbox in-app polimórfico.
class CreateParcelWatchesAndNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :parcel_watches do |t|
      t.references :user,   null: false, foreign_key: true
      t.references :parcel, null: false, foreign_key: true
      t.integer  :notify_days_before, null: false, default: 7
      t.boolean  :in_app_enabled,     null: false, default: true
      t.boolean  :email_enabled,      null: false, default: false
      t.datetime :last_notified_at
      t.timestamps
    end
    add_index :parcel_watches, [:user_id, :parcel_id], unique: true

    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string   :notifiable_type, null: false
      t.bigint   :notifiable_id,   null: false
      t.string   :kind,            null: false
      t.string   :delivery_channel, null: false, default: "in_app"
      t.datetime :read_at
      t.jsonb    :payload, null: false, default: {}
      t.timestamps
    end
    add_index :notifications, [:notifiable_type, :notifiable_id]
    add_index :notifications, [:user_id, :read_at]

    add_column :users, :default_notify_days_before, :integer, null: false, default: 7
    add_column :users, :email_notifications_enabled, :boolean, null: false, default: false
  end
end
