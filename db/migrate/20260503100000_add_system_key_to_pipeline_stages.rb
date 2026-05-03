# frozen_string_literal: true

# Identificador estable de stages que el sistema necesita ubicar
# programáticamente aunque el usuario los renombre. Por ahora:
#   'archived' → destino de ArchivePostAuctionPipelineJob (7 días post sale_date)
#   'won'      → respetado por el archivado automático
class AddSystemKeyToPipelineStages < ActiveRecord::Migration[7.1]
  def up
    add_column :pipeline_stages, :system_key, :string, limit: 30

    add_index :pipeline_stages,
              [:user_id, :system_key],
              name: "idx_pipeline_stages_user_system_key",
              where: "system_key IS NOT NULL"

    # Backfill por nombre canónico de los DEFAULT_STAGES seedeados.
    execute <<~SQL.squish
      UPDATE pipeline_stages
         SET system_key = 'archived'
       WHERE name = 'Archived' AND is_default = TRUE
    SQL

    execute <<~SQL.squish
      UPDATE pipeline_stages
         SET system_key = 'won'
       WHERE name = 'Won' AND is_default = TRUE
    SQL
  end

  def down
    remove_index :pipeline_stages, name: "idx_pipeline_stages_user_system_key"
    remove_column :pipeline_stages, :system_key
  end
end
