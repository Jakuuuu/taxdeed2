# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════════════
# 🧹 RETROACTIVE DATA CLEANUP — Parcels con sqft inflados
#
# ⛔ CRM IMMUNITY: Este script NO toca parcel_user_tags ni parcel_user_notes.
# Solo modifica sqft_lot y sqft_living en registros donde los valores son
# sospechosamente altos (inflación por el bug de Sanitize.integer).
#
# USO:
#   rails runner lib/tasks/fix_inflated_sqft.rb
#
# O en rails console:
#   load "lib/tasks/fix_inflated_sqft.rb"
# ═══════════════════════════════════════════════════════════════════════════════

include ActionView::Helpers::NumberHelper

puts "=" * 70
puts "🔬 AUDITORÍA DE INTEGRIDAD: sqft_lot & sqft_living"
puts "=" * 70
puts ""

# ── Umbrales de detección ──────────────────────────────────────────────────────
SQFT_LIVING_THRESHOLD = 50_000
SQFT_LOT_THRESHOLD    = 500_000

# ── FASE 1: Auditoría ─────────────────────────────────────────────────────────
suspect_living = Parcel.where("sqft_living > ?", SQFT_LIVING_THRESHOLD)
                       .where("sqft_living > 0")
                       .order(sqft_living: :desc)

suspect_lot = Parcel.where("sqft_lot > ?", SQFT_LOT_THRESHOLD)
                    .where("sqft_lot > 0")
                    .order(sqft_lot: :desc)

fmt = ->(n) { number_with_delimiter(n.to_i) }

puts "📊 SQFT_LIVING sospechosos (> #{fmt.call(SQFT_LIVING_THRESHOLD)}):"
puts "-" * 70
if suspect_living.any?
  suspect_living.each do |p|
    deflated = (p.sqft_living / 100).round(0)
    pattern = p.sqft_living.to_i % 100 == 0 ? "✅ patrón 100x" : "⚠️ irregular"
    puts "  ID: #{p.id} | #{p.county}, #{p.state} | sqft_living: #{fmt.call(p.sqft_living)} | /100 = #{fmt.call(deflated)} | #{pattern}"
  end
else
  puts "  ✅ Ninguno encontrado"
end

puts ""
puts "📊 SQFT_LOT sospechosos (> #{fmt.call(SQFT_LOT_THRESHOLD)}):"
puts "-" * 70
if suspect_lot.any?
  suspect_lot.each do |p|
    deflated = (p.sqft_lot / 100).round(0)
    pattern = p.sqft_lot.to_i % 100 == 0 ? "✅ patrón 100x" : "⚠️ irregular"
    puts "  ID: #{p.id} | #{p.county}, #{p.state} | sqft_lot: #{fmt.call(p.sqft_lot)} | /100 = #{fmt.call(deflated)} | #{pattern}"
  end
else
  puts "  ✅ Ninguno encontrado"
end

total_suspects = suspect_living.count + suspect_lot.count

puts ""
puts "=" * 70
puts "📈 RESUMEN: #{total_suspects} registros sospechosos en total"
puts "   Total parcels en BD: #{Parcel.count}"
puts "   Con sqft_living: #{Parcel.where.not(sqft_living: nil).where('sqft_living > 0').count}"
puts "   Con sqft_lot:    #{Parcel.where.not(sqft_lot: nil).where('sqft_lot > 0').count}"
puts "=" * 70

# ── Muestra adicional: verificar el rango normal de sqft ────────────────────
puts ""
puts "📊 DISTRIBUCIÓN DE RANGOS (sqft_living con datos):"
ranges = {
  "0-500"        => [0, 500],
  "500-1,500"    => [500, 1_500],
  "1,500-3,000"  => [1_500, 3_000],
  "3,000-10,000" => [3_000, 10_000],
  "10,000-50,000"=> [10_000, 50_000],
  "> 50,000"     => [50_000, 999_999_999]
}
ranges.each do |label, (lo, hi)|
  count = Parcel.where("sqft_living > ? AND sqft_living <= ?", lo, hi).count
  puts "  #{label.ljust(15)} → #{count} parcels"
end

puts ""
puts "📊 MUESTRA — Top 10 sqft_living más altos:"
puts "-" * 70
Parcel.where.not(sqft_living: nil).where("sqft_living > 0").order(sqft_living: :desc).limit(10).each do |p|
  puts "  ID: #{p.id} | #{p.address} | #{p.county}, #{p.state} | sqft_living: #{fmt.call(p.sqft_living)}"
end

puts ""
puts "📊 MUESTRA — Top 10 sqft_lot más altos:"
puts "-" * 70
Parcel.where.not(sqft_lot: nil).where("sqft_lot > 0").order(sqft_lot: :desc).limit(10).each do |p|
  puts "  ID: #{p.id} | #{p.address} | #{p.county}, #{p.state} | sqft_lot: #{fmt.call(p.sqft_lot)}"
end

puts ""
puts "💡 PRÓXIMO PASO: Si hay registros sospechosos, el siguiente sync"
puts "   (SyncSheetJob.perform_now) aplicará el sanitizer corregido"
puts "   y sobreescribirá los valores inflados con los correctos del Sheet."
