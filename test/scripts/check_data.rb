p = Parcel.where.not(electric: nil).first
if p
  puts "ID=#{p.id} electric=#{p.electric.inspect} water=#{p.water.inspect} sewer=#{p.sewer.inspect} hoa=#{p.hoa.inspect}"
else
  puts "No parcels with utilities data"
end
puts "---"
p2 = Parcel.first
if p2
  puts "First parcel: ID=#{p2.id} state=#{p2.state} county=#{p2.county} parcel_id=#{p2.parcel_id}"
  puts "Total parcels: #{Parcel.count}"
else
  puts "No parcels in DB"
end
puts "---"
puts "SyncLog columns: #{SyncLog.column_names.join(', ')}"
puts "SyncLog count: #{SyncLog.count}"
last = SyncLog.order(created_at: :desc).first
if last
  puts "Last SyncLog: status=#{last.status} added=#{last.parcels_added} updated=#{last.parcels_updated}"
end
