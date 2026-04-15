# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════════════
# MIGRACIÓN: Blindaje NOT NULL para columnas de identidad de parcels
# ═══════════════════════════════════════════════════════════════════════════════
#
# Problema: El UNIQUE INDEX idx_parcels_unique_state_county_pid existe, pero
# las columnas (state, county, parcel_id) permiten NULL. En SQL estándar,
# NULL ≠ NULL, por lo que el índice NO bloquea duplicados con valores NULL.
#
# Solución:
#   Fase 1 — Data Cleanup: eliminar registros con NULL/blank en las 3 columnas
#            de identidad, cascadeando la limpieza a tablas dependientes.
#   Fase 2 — NOT NULL: aplicar constraint NOT NULL a las 3 columnas.
#
# ⛔ CRM IMMUNITY: Los registros eliminados en Fase 1 son "basura estructural"
#    (parcelas sin identidad válida). Si tienen datos CRM asociados, esos datos
#    son huérfanos y no pueden ser mostrados al usuario de todas formas.
#
class AddNotNullConstraintsToParcelsIdentifiers < ActiveRecord::Migration[7.2]
  def up
    # ═══════════════════════════════════════════════════════════════════════════
    # PHASE 1: Data Cleanup — eliminar parcelas con NULL/blank en identifiers
    # ═══════════════════════════════════════════════════════════════════════════
    # Sin esta limpieza, change_column_null fallará si hay NULLs existentes.

    say_with_time "Phase 1: Removing parcels with NULL/blank identifiers" do
      invalid_ids = connection.select_values(<<~SQL)
        SELECT id FROM parcels
        WHERE state IS NULL OR TRIM(state) = ''
           OR county IS NULL OR TRIM(county) = ''
           OR parcel_id IS NULL OR TRIM(parcel_id) = ''
      SQL

      if invalid_ids.any?
        id_list = invalid_ids.join(",")
        say "  → Found #{invalid_ids.size} invalid parcels — cleaning dependents and deleting"

        # Cascade-delete dependents before removing the parcels
        execute "DELETE FROM parcel_user_tags  WHERE parcel_id IN (#{id_list})"
        execute "DELETE FROM parcel_user_notes WHERE parcel_id IN (#{id_list})"
        execute "DELETE FROM viewed_parcels    WHERE parcel_id IN (#{id_list})"
        execute "DELETE FROM reports           WHERE parcel_id IN (#{id_list})"
        execute "DELETE FROM parcel_liens      WHERE parcel_id IN (#{id_list})"

        # credit_transactions might reference parcel_id (nullable FK)
        if connection.table_exists?("credit_transactions")
          execute "UPDATE credit_transactions SET parcel_id = NULL WHERE parcel_id IN (#{id_list})"
        end

        execute "DELETE FROM parcels WHERE id IN (#{id_list})"
      else
        say "  → No invalid parcels found — database is clean"
      end

      invalid_ids.size
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PHASE 2: Apply NOT NULL constraints
    # ═══════════════════════════════════════════════════════════════════════════
    # Después de la limpieza, es seguro aplicar los constraints.

    say_with_time "Phase 2: Adding NOT NULL constraints to state, county, parcel_id" do
      change_column_null :parcels, :state, false
      change_column_null :parcels, :county, false
      change_column_null :parcels, :parcel_id, false
    end
  end

  def down
    change_column_null :parcels, :state, true
    change_column_null :parcels, :county, true
    change_column_null :parcels, :parcel_id, true
  end
end
