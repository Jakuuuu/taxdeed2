# frozen_string_literal: true

# ════════════════════════════════════════════════════════════════════════════
# Backfill one-shot: corrige el SWAP histórico de bathrooms ↔ bedrooms.
#
# Contexto:
#   Hasta hoy, SheetRowProcessor mapeaba al revés las columnas O y P del
#   Sheet "Propiedades1":
#     - col O "Habitaciones" (= bedrooms) → bathrooms  ❌
#     - col P "BD"           (= bathrooms) → bedrooms  ❌
#
#   El processor ya fue corregido. Este script invierte los valores
#   YA almacenados en BD para parcelas con datos sincronizados antes
#   del fix.
#
# Uso:
#   bundle exec rails runner active/swap_bathrooms_bedrooms_backfill.rb
#
# Ejecutar UNA SOLA VEZ. Tras verificar el resultado, eliminar este archivo.
# ════════════════════════════════════════════════════════════════════════════

scope = Parcel.where("bathrooms IS NOT NULL OR bedrooms IS NOT NULL")
total = scope.count

puts "[backfill] Parcelas a procesar: #{total}"

processed = 0
skipped   = 0

ActiveRecord::Base.transaction do
  scope.find_each(batch_size: 500) do |p|
    old_bathrooms = p.bathrooms  # decimal(3,1) → BigDecimal o nil
    old_bedrooms  = p.bedrooms   # integer      → Integer o nil

    new_bathrooms = old_bedrooms.present? ? BigDecimal(old_bedrooms.to_s) : nil
    new_bedrooms  = old_bathrooms.present? ? old_bathrooms.to_i : nil

    if old_bathrooms == new_bathrooms && old_bedrooms == new_bedrooms
      skipped += 1
      next
    end

    p.update_columns(bathrooms: new_bathrooms, bedrooms: new_bedrooms)
    processed += 1
  end
end

puts "[backfill] ✅ Completado. Swap aplicado: #{processed} | Sin cambios: #{skipped}"
puts "[backfill] ⚠️ Eliminar este script tras verificar (active/swap_bathrooms_bedrooms_backfill.rb)"
