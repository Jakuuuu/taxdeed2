# frozen_string_literal: true

# ArchivePostAuctionPipelineJob — Mueve al stage 'Archived' las cards del
# Pipeline cuya subasta ya pasó hace más de 7 días, para que el board no se
# llene de propiedades vencidas.
#
# Reglas:
#   - Respeta stages con system_key 'won' (el usuario ganó) y 'archived'
#     (ya está donde debería). NO los toca.
#   - Mueve usando PipelineProperty#move_to! → preserva la sync con CRM tag
#     (aunque Archived no tiene crm_tag_map, así que es no-op por ese lado).
#   - Si el usuario no tiene un stage con system_key='archived' (caso raro:
#     creado antes de la migración + sin re-seed), skip silencioso.
#
# Cron sugerido: diario 06:30 UTC = 02:30 AM ET (después de expire_auctions).
class ArchivePostAuctionPipelineJob < ApplicationJob
  queue_as :default

  ARCHIVE_AFTER_DAYS = 7

  def perform
    cutoff  = Date.current - ARCHIVE_AFTER_DAYS.days
    moved   = 0
    skipped = 0

    PipelineProperty
      .joins(:pipeline_stage, parcel: :auction)
      .where("auctions.sale_date < ?", cutoff)
      .where.not(pipeline_stages: { system_key: [PipelineStage::SYSTEM_KEY_ARCHIVED, PipelineStage::SYSTEM_KEY_WON] })
      .includes(:user, parcel: :auction)
      .find_each do |pp|
        archived_stage = pp.user.pipeline_stages.find_by(system_key: PipelineStage::SYSTEM_KEY_ARCHIVED)

        if archived_stage.nil?
          skipped += 1
          next
        end

        pp.move_to!(archived_stage)
        moved += 1
      end

    Rails.logger.info "[ArchivePostAuctionPipelineJob] ✅ archivadas=#{moved} skipped=#{skipped}"
  end
end
