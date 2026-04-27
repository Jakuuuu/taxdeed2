# frozen_string_literal: true

module Research
  class PortfolioController < BaseController
    # GET /research/portfolio
    # ══════════════════════════════════════════════════════════════════════
    # Rama 5: My Portfolio — lista todas las parcelas con las que el usuario
    # ha interactuado: desbloqueadas (viewed_parcels) + con tag o nota CRM.
    #
    # Anti-N+1: 5 queries fijas sin importar el volumen de parcelas.
    #   Q1: ParcelUserTag  → tags_by_parcel Hash + tagged_ids
    #   Q2: ParcelUserNote → note_counts Hash + noted_ids
    #   Q3: ViewedParcel   → unlocked_ids Array
    #   Q4: Parcel.where(id: union).includes(:auction) — única query de carga
    # ══════════════════════════════════════════════════════════════════════
    def show
      # Q1 — Tags: un registro por parcela (UNIQUE INDEX en user_id+parcel_id)
      tag_records     = ParcelUserTag.where(user_id: current_user.id).to_a
      @tags_by_parcel = tag_records.index_by(&:parcel_id)
      tagged_ids      = tag_records.map(&:parcel_id)

      # Q2 — Notes: cuenta por parcela (GROUP BY), devuelve Hash {parcel_id => count}
      @note_counts = ParcelUserNote.where(user_id: current_user.id)
                                   .group(:parcel_id).count
      noted_ids    = @note_counts.keys

      # Q3 — Unlocked: toda viewed_parcels = unlock (sin columna booleana, la existencia es el unlock)
      unlocked_ids  = ViewedParcel.where(user_id: current_user.id).pluck(:parcel_id)
      @unlocked_set = Set.new(unlocked_ids)

      # Union de los tres conjuntos — sin duplicados
      parcel_ids = (unlocked_ids | tagged_ids | noted_ids)

      # Q4 — Carga de parcelas con auction eager-loaded
      @parcels = if parcel_ids.any?
        Parcel.where(id: parcel_ids)
              .includes(:auction)
              .order(updated_at: :desc)
      else
        Parcel.none
      end

      @empty = @parcels.empty?
    end
  end
end
