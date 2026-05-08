# frozen_string_literal: true
puts "[A] SheetColumnMap::NOTAS = #{SheetColumnMap::NOTAS}"
puts "[B] IGNORED_INTERNAL includes 5 (Comments): #{SheetColumnMap::IGNORED_INTERNAL.include?(5)}"
puts "[C] IGNORED_INTERNAL excludes 4 (Notes):    #{!SheetColumnMap::IGNORED_INTERNAL.include?(4)}"
puts
puts "[D] Parcels seedeados:"
Parcel.where(clear_to_bid_grade_locked: true).order(:id).each do |p|
  poly = p.polygon_encoded.present? ? "len=#{p.polygon_encoded.length}" : "nil (marker fallback)"
  puts "    id=#{p.id.to_s.rjust(5)} county=#{p.county.ljust(15)} grade=#{p.clear_to_bid_grade.ljust(11)} polygon=#{poly}"
end
puts
puts "[E] Helper output for a parcel with polygon:"
parcel = Parcel.where.not(polygon_encoded: nil).first
ctx = Class.new { include ClearToBidHelper }.new
url = ctx.static_map_url(parcel).to_s
puts "    parcel_id=#{parcel.id} county=#{parcel.county}"
puts "    URL contains 'path=': #{url.include?('path=')}"
puts "    URL contains 'enc:':  #{url.include?('enc:') || url.include?('enc%3A')}"
puts "    URL contains E67E22:  #{url.upcase.include?('E67E22')}"
puts "    URL length:           #{url.length}"
puts
puts "[F] Helper output for a parcel WITHOUT polygon (fallback):"
parcel2 = Parcel.where(clear_to_bid_grade_locked: true, polygon_encoded: nil).first
url2 = ctx.static_map_url(parcel2).to_s
puts "    parcel_id=#{parcel2.id} county=#{parcel2.county}"
puts "    URL contains 'markers=': #{url2.include?('markers=')}"
puts "    URL contains 'zoom=18':  #{url2.include?('zoom=18')}"
puts "    URL length:              #{url2.length}"
