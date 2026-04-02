# frozen_string_literal: true

class CreateSupportingTables < ActiveRecord::Migration[7.2]
  def change

    # PARCEL LIENS
    create_table :parcel_liens do |t|
      t.references :parcel, null: false, foreign_key: true
      t.string  :lender_name,   limit: 200
      # mortgage | lien | judgment | irs
      t.string  :lien_type,     limit: 30
      t.decimal :amount,        precision: 12, scale: 2
      t.date    :recorded_date
      # active | released | unknown
      t.string  :status,        limit: 20

      t.timestamps null: false
    end

    # REPORTS (avm | property_scope | title_search)
    create_table :reports do |t|
      t.references :user,   null: false, foreign_key: true
      t.references :parcel, null: false, foreign_key: true
      # avm | property_scope | title_search -- NO otc en esta version
      t.string    :report_type, null: false, limit: 30
      # pending | ordered | generated | failed
      t.string    :status,      default: "pending"
      t.string    :download_url, limit: 500
      t.integer   :file_size_bytes
      t.string    :provider_ref, limit: 100
      t.datetime  :ordered_at
      t.datetime  :generated_at

      t.timestamps null: false
    end

    # NOTE: index_reports_on_user_id and index_reports_on_parcel_id auto-created by t.references
    add_index :reports, [:user_id, :parcel_id, :report_type],
              unique: true,
              where: "status != 'failed'",
              name: "idx_reports_user_parcel_type",
              if_not_exists: true

    # VIEWED PARCELS (historial de vistas por usuario)
    create_table :viewed_parcels do |t|
      t.references :user,   null: false, foreign_key: true
      t.references :parcel, null: false, foreign_key: true
      t.datetime   :viewed_at, null: false, default: -> { "CURRENT_TIMESTAMP" }

      t.timestamps null: false
    end

    # NOTE: index_viewed_parcels_on_user_id and _on_parcel_id auto-created by t.references
    add_index :viewed_parcels, [:user_id, :parcel_id], unique: true,
              name: "idx_viewed_parcels_user_parcel",
              if_not_exists: true
  end
end