# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════════════
# MIGRACIÓN: Blindaje anti-duplicados para parcels
# ═══════════════════════════════════════════════════════════════════════════════
#
# Problema: SyncSheetJob puede generar registros duplicados en parcels porque
# no existe un UNIQUE INDEX a nivel de base de datos. La lógica de aplicación
# (find_or_initialize_by) es insuficiente ante race conditions o errores.
#
# Solución en 2 fases:
#   Fase 1 — Data Cleanup: elimina parcelas inválidas (NULL identifiers) y
#            fusiona duplicados existentes, reasignando FKs para proteger datos CRM.
#   Fase 2 — UNIQUE INDEX: aplica constraint compuesto (state, county, parcel_id)
#            para que PostgreSQL bloquee físicamente la creación de duplicados.
#
# ⛔ CRM IMMUNITY: La reasignación de FKs garantiza que parcel_user_tags y
#    parcel_user_notes NUNCA se pierdan durante la fusión de duplicados.
#
class AddUniqueIndexParcelsStateCountyParcelId < ActiveRecord::Migration[7.2]
  def up
    # ═══════════════════════════════════════════════════════════════════════════
    # PHASE 1a: Remove structurally invalid parcels (NULL/blank identifiers)
    # ═══════════════════════════════════════════════════════════════════════════
    # En Tax Deeds, una parcela sin state, county, o parcel_id es basura
    # estructural: el frontend (mapas Rama 2), el Blur Paywall, y el sistema
    # de créditos no pueden funcionar sin estos tres campos.

    say_with_time "Phase 1a: Removing parcels with NULL/blank identifiers" do
      invalid_ids = connection.select_values(<<~SQL)
        SELECT id FROM parcels
        WHERE state IS NULL OR TRIM(state) = ''
           OR county IS NULL OR TRIM(county) = ''
           OR parcel_id IS NULL OR TRIM(parcel_id) = ''
      SQL

      if invalid_ids.any?
        id_list = invalid_ids.join(",")
        say "  → Found #{invalid_ids.size} invalid parcels — cleaning dependents and deleting"

        # Cascade-delete dependents before removing the parcels themselves
        execute "DELETE FROM parcel_user_tags  WHERE parcel_id IN (#{id_list})"
        execute "DELETE FROM parcel_user_notes WHERE parcel_id IN (#{id_list})"
        execute "DELETE FROM viewed_parcels    WHERE parcel_id IN (#{id_list})"
        execute "DELETE FROM reports           WHERE parcel_id IN (#{id_list})"
        execute "DELETE FROM parcel_liens      WHERE parcel_id IN (#{id_list})"
        execute "DELETE FROM credit_transactions WHERE parcel_id IN (#{id_list})"
        execute "DELETE FROM parcels           WHERE id IN (#{id_list})"
      else
        say "  → No invalid parcels found"
      end

      invalid_ids.size
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PHASE 1b: Merge duplicate parcels (keep lowest id as survivor per group)
    # ═══════════════════════════════════════════════════════════════════════════
    # For each duplicate group (same state+county+parcel_id):
    #   1. Keep the record with the LOWEST id (the original)
    #   2. Reassign all FK references from duplicates → survivor
    #   3. Respect unique constraints on dependent tables (tags, viewed_parcels)
    #   4. Preserve unlock status (viewed_parcels.unlocked = TRUE persists)
    #   5. Delete the duplicate parcel records

    say_with_time "Phase 1b: Merging duplicate parcels by (state, county, parcel_id)" do
      groups = connection.select_all(<<~SQL)
        SELECT MIN(id) AS survivor_id,
               ARRAY_AGG(id ORDER BY id) AS all_ids,
               state, county, parcel_id,
               COUNT(*) AS cnt
        FROM parcels
        WHERE state IS NOT NULL AND county IS NOT NULL AND parcel_id IS NOT NULL
        GROUP BY state, county, parcel_id
        HAVING COUNT(*) > 1
      SQL

      if groups.empty?
        say "  → No duplicate parcels found"
        next 0
      end

      say "  → Found #{groups.size} duplicate groups to merge"
      merged_count = 0

      groups.each do |group|
        survivor_id = group["survivor_id"].to_i
        # Parse PostgreSQL array literal "{1,2,3}" → [1, 2, 3]
        raw_ids = group["all_ids"].to_s.gsub(/[{}]/, "").split(",").map(&:to_i)
        dup_ids = raw_ids.reject { |id| id == survivor_id }
        next if dup_ids.empty?

        dup_list = dup_ids.join(",")

        # ── parcel_user_tags: UNIQUE(user_id, parcel_id) ────────────────
        # Reassign only if no conflict (same user doesn't already have a tag on survivor)
        execute <<~SQL
          UPDATE parcel_user_tags
          SET parcel_id = #{survivor_id}
          WHERE parcel_id IN (#{dup_list})
            AND NOT EXISTS (
              SELECT 1 FROM parcel_user_tags t2
              WHERE t2.parcel_id = #{survivor_id}
                AND t2.user_id = parcel_user_tags.user_id
            )
        SQL
        # Delete remaining conflicting tags (survivor's tag wins)
        execute "DELETE FROM parcel_user_tags WHERE parcel_id IN (#{dup_list})"

        # ── parcel_user_notes: NO unique constraint on (user_id, parcel_id) ─
        # Safe to bulk reassign — all notes are preserved
        execute "UPDATE parcel_user_notes SET parcel_id = #{survivor_id} WHERE parcel_id IN (#{dup_list})"

        # ── viewed_parcels: UNIQUE(user_id, parcel_id) ──────────────────
        # Before reassigning, propagate unlock status to survivor
        # If any duplicate has unlocked=TRUE for a user, the survivor should too
        execute <<~SQL
          UPDATE viewed_parcels vp_survivor
          SET unlocked = TRUE,
              unlocked_at = COALESCE(vp_survivor.unlocked_at, vp_dup.unlocked_at),
              credits_spent = GREATEST(vp_survivor.credits_spent, vp_dup.credits_spent)
          FROM viewed_parcels vp_dup
          WHERE vp_dup.parcel_id IN (#{dup_list})
            AND vp_survivor.parcel_id = #{survivor_id}
            AND vp_survivor.user_id = vp_dup.user_id
            AND vp_dup.unlocked = TRUE
            AND vp_survivor.unlocked = FALSE
        SQL
        # Reassign non-conflicting viewed_parcels
        execute <<~SQL
          UPDATE viewed_parcels
          SET parcel_id = #{survivor_id}
          WHERE parcel_id IN (#{dup_list})
            AND NOT EXISTS (
              SELECT 1 FROM viewed_parcels vp2
              WHERE vp2.parcel_id = #{survivor_id}
                AND vp2.user_id = viewed_parcels.user_id
            )
        SQL
        # Delete remaining conflicting viewed_parcels (survivor record preserved)
        execute "DELETE FROM viewed_parcels WHERE parcel_id IN (#{dup_list})"

        # ── reports: conditional UNIQUE(user_id, parcel_id, report_type)
        #             WHERE status != 'failed' ──────────────────────────
        execute <<~SQL
          UPDATE reports
          SET parcel_id = #{survivor_id}
          WHERE parcel_id IN (#{dup_list})
            AND NOT EXISTS (
              SELECT 1 FROM reports r2
              WHERE r2.parcel_id = #{survivor_id}
                AND r2.user_id = reports.user_id
                AND r2.report_type = reports.report_type
                AND r2.status != 'failed'
                AND reports.status != 'failed'
            )
        SQL
        execute "DELETE FROM reports WHERE parcel_id IN (#{dup_list})"

        # ── parcel_liens: NO unique constraint ──────────────────────────
        execute "UPDATE parcel_liens SET parcel_id = #{survivor_id} WHERE parcel_id IN (#{dup_list})"

        # ── credit_transactions: references parcel_id (nullable) ────────
        execute "UPDATE credit_transactions SET parcel_id = #{survivor_id} WHERE parcel_id IN (#{dup_list})"

        # ── DELETE the duplicate parcels ────────────────────────────────
        execute "DELETE FROM parcels WHERE id IN (#{dup_list})"

        merged_count += dup_ids.size
      end

      say "  → Merged #{merged_count} duplicate parcels into their survivors"
      merged_count
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PHASE 2: Apply UNIQUE composite index
    # ═══════════════════════════════════════════════════════════════════════════
    # This is the PostgreSQL-level shield: after this, the database will
    # physically reject any INSERT/UPDATE that creates a duplicate
    # (state, county, parcel_id) combination.

    say_with_time "Phase 2: Adding UNIQUE composite index on parcels(state, county, parcel_id)" do
      add_index :parcels, [:state, :county, :parcel_id],
                unique: true,
                name: "idx_parcels_unique_state_county_pid"
    end
  end

  def down
    remove_index :parcels, name: "idx_parcels_unique_state_county_pid"
  end
end
