#!/usr/bin/env ruby
# frozen_string_literal: true
# Seed real: asigna grades a parcels en condados con polígono soportado
# y dispara EncodeParcelPolygonJob sincrónicamente.

puts "=" * 70
puts "  CLEAR-TO-BID — SEED REAL + POLYGON ENCODE"
puts "=" * 70

# Mapeo: condado → grade a asignar (mix variado para verificar el catálogo)
SEED_PLAN = {
  "Palm Beach"   => "optimo",
  "Brevard"      => "viable",
  "Hillsborough" => "optimo",
  "Marion"       => "viable",
  "Putnam"       => "deficiente",  # Para verificar que NO aparece en catálogo (scope filtra deficiente)
  "Washington"   => "viable"
}.freeze

# Helper local: calificación de tabla para evitar ambigüedad cuando se hace join.
parcels_in_county = ->(county) {
  Parcel.where("LOWER(parcels.county) = ?", county.to_s.downcase)
}

puts "\n[1] Conteo de parcels por condado registrado en GIS:"
SEED_PLAN.keys.each do |county|
  count       = parcels_in_county.call(county).count
  with_coords = parcels_in_county.call(county).has_coords.count
  puts "    #{county.ljust(15)} parcels=#{count.to_s.rjust(5)}  con coords=#{with_coords.to_s.rjust(4)}"
end

puts "\n[2] Seedeando 1 parcel por condado (con coords):"
seeded = []
SEED_PLAN.each do |county, grade|
  parcel = parcels_in_county.call(county).has_coords.order(:id).first
  if parcel.nil?
    puts "    #{county.ljust(15)} ⚠️  no hay parcel con coords — skip"
    next
  end
  parcel.update_column(:clear_to_bid_grade, grade)
  parcel.update_column(:clear_to_bid_grade_locked, true)  # lock contra futuro sync
  seeded << parcel
  puts "    #{county.ljust(15)} parcel_id=#{parcel.id.to_s.rjust(5)} (#{parcel.parcel_id}) → grade=#{grade.ljust(10)} (locked)"
end

puts "\n[3] Ejecutando ParcelPolygonEncoder sincrónicamente (real ArcGIS REST):"
seeded.each do |p|
  print "    parcel_id=#{p.id.to_s.rjust(5)} county=#{p.county.ljust(15)} ... "
  encoded = ParcelPolygonEncoder.encode_for(p)
  if encoded.present?
    p.update_column(:polygon_encoded, encoded)
    puts "✅ polygon_encoded len=#{encoded.length}"
  else
    puts "⚠️  no polygon (county fuera del registry o ArcGIS sin features)"
  end
end

puts "\n[4] Estado final:"
ctb = Parcel.clear_to_bid.count
with_poly = Parcel.clear_to_bid.where.not(polygon_encoded: nil).count
deficiente = Parcel.where(clear_to_bid_grade: "deficiente").count
locked = Parcel.where(clear_to_bid_grade_locked: true).count

puts "    parcels en scope clear_to_bid (viable+optimo): #{ctb}"
puts "      └─ con polygon_encoded: #{with_poly}"
puts "    parcels grade=deficiente (excluidos del scope): #{deficiente}"
puts "    parcels con lock activo: #{locked}"

puts "\n[5] Distribución por grade (todas):"
Parcel.where.not(clear_to_bid_grade: nil)
      .group(:clear_to_bid_grade)
      .count
      .sort
      .each { |g, c| puts "    #{g.ljust(15)} → #{c}" }

puts "\n[6] Verificación: payload teaser NO leak para no-Premier"
include_concern = Class.new { include ClearToBidPayload }.new
sample_relation = Parcel.clear_to_bid.select(:id, :state, :county, :clear_to_bid_grade).limit(2)
teaser = include_concern.clear_to_bid_skeleton(sample_relation).first
puts "    teaser keys = #{teaser&.keys&.sort.inspect}"
forbidden = %i[address parcel_id latitude longitude opening_bid polygon_encoded]
leak = forbidden & (teaser&.keys || [])
puts "    leak check  = #{leak.empty? ? "✅ no leak" : "❌ #{leak.inspect}"}"

puts "\n[7] Verificación: payload full SÍ incluye polygon_encoded para Premier"
full_relation = Parcel.clear_to_bid.includes(:auction).limit(2)
full = include_concern.clear_to_bid_full(full_relation).first
puts "    full keys = #{full&.keys&.sort.inspect}"
puts "    polygon_encoded present in full → #{full&.key?(:polygon_encoded) ? "✅" : "❌"}"

puts "\n" + "=" * 70
puts "  COMPLETADO — abre http://127.0.0.1:3000/research/clear_to_bid"
puts "  (necesitas login con suscripción premier+active para ver @parcels_full)"
puts "=" * 70
