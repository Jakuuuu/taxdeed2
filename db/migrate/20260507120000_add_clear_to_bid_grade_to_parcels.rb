# frozen_string_literal: true

# Rama 6 — Clear-to-Bid: añade clear_to_bid_grade a parcels.
# Vocabulario controlado: 'deficiente' | 'viable' | 'optimo' (lowercase, ASCII).
# Origen: columna F "Notas" del Google Sheet → SheetRowProcessor#derive_clear_to_bid_grade.
# Override manual: Admin::ParcelsController#update.
class AddClearToBidGradeToParcels < ActiveRecord::Migration[7.2]
  def change
    add_column :parcels, :clear_to_bid_grade, :string

    # Index parcial: solo parcelas clasificadas (la mayoría serán nil).
    add_index :parcels,
              :clear_to_bid_grade,
              where: "clear_to_bid_grade IS NOT NULL",
              name:  "index_parcels_on_clear_to_bid_grade_not_null"
  end
end
