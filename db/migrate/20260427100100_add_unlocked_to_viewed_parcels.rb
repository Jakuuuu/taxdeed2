# frozen_string_literal: true

class AddUnlockedToViewedParcels < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    change_table :viewed_parcels, bulk: true do |t|
      t.boolean  :unlocked,      null: false, default: false
      t.datetime :unlocked_at
      t.integer  :credits_spent, null: false, default: 0
    end

    # Backfill: cualquier registro existente representaba un acceso a la
    # ficha — bajo el modelo previo eso equivalía a desbloqueado.
    execute <<~SQL
      UPDATE viewed_parcels
      SET unlocked = TRUE,
          unlocked_at = viewed_at
      WHERE unlocked = FALSE
    SQL

    add_index :viewed_parcels,
              [:user_id, :unlocked],
              where: "unlocked = TRUE",
              name: "idx_viewed_parcels_unlocked",
              algorithm: :concurrently
  end

  def down
    remove_index :viewed_parcels, name: "idx_viewed_parcels_unlocked"
    change_table :viewed_parcels, bulk: true do |t|
      t.remove :unlocked, :unlocked_at, :credits_spent
    end
  end
end
