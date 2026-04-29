# frozen_string_literal: true

class CreatePipelineTables < ActiveRecord::Migration[7.1]
  def change
    # ── Pipeline Stages (columnas personalizables del Kanban) ──
    create_table :pipeline_stages do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string  :name,        null: false, limit: 100
      t.string  :emoji,       limit: 10
      t.string  :color,       limit: 30
      t.integer :position,    null: false
      t.boolean :is_default,  default: false
      t.string  :crm_tag_map, limit: 50  # 'target'|'diligence'|'ready'|'dismissed'|NULL
      t.timestamps
    end
    add_index :pipeline_stages, [:user_id, :position], name: "idx_pipeline_stages_user"

    # ── Pipeline Properties (propiedades asignadas a stages) ──
    create_table :pipeline_properties do |t|
      t.references :user,           null: false, foreign_key: { on_delete: :cascade }
      t.references :parcel,         null: false, foreign_key: { on_delete: :cascade }
      t.references :pipeline_stage, null: false, foreign_key: { on_delete: :cascade }
      t.integer    :position,       null: false, default: 0
      t.datetime   :added_at,       null: false, default: -> { "NOW()" }
      t.timestamps
    end
    add_index :pipeline_properties, [:user_id, :parcel_id],
              unique: true, name: "idx_pipeline_props_user_parcel"
    add_index :pipeline_properties, [:pipeline_stage_id, :position],
              name: "idx_pipeline_props_stage"
  end
end
