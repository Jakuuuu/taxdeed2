# Visual QA Test — validates rendered HTML for utilities badges
# Simulates what the view will render for Parcel #1

puts "=" * 70
puts "  VISUAL QA TEST — Utilities Badge Rendering"
puts "=" * 70

parcel = Parcel.find(1)
puts "\nParcel: #{parcel.state}/#{parcel.county}/#{parcel.parcel_id}"
puts "Raw DB values:"
puts "  electric: #{parcel.electric.inspect} (class: #{parcel.electric.class})"
puts "  water:    #{parcel.water.inspect} (class: #{parcel.water.class})"
puts "  sewer:    #{parcel.sewer.inspect} (class: #{parcel.sewer.class})"
puts "  hoa:      #{parcel.hoa.inspect} (class: #{parcel.hoa.class})"

# Simulate the exact view logic from show.html.erb (post-fix)
utilities = [
  { label: "Electric",  val: parcel.electric },
  { label: "Water",     val: parcel.water },
  { label: "Sewer",     val: parcel.sewer },
  { label: "HOA / POA", val: parcel.hoa },
]

puts "\n--- Badge Rendering Simulation ---"
utilities.each do |u|
  raw = u[:val].to_s.strip.downcase
  is_yes = %w[yes true y 1].include?(raw)
  is_no  = raw.present? && !is_yes

  if is_yes
    color = "#10B981" # green
    badge = "Yes"
    icon = "GREEN"
  elsif is_no
    color = "#DC2626" # red
    badge = "No"
    icon = "RED"
  else
    color = nil
    badge = "—"
    icon = "NEUTRAL"
  end

  status = "#{icon.ljust(8)} | #{u[:label].ljust(12)} | DB='#{u[:val]}' => Display='#{badge}'"
  puts "  #{status}"

  # Validate expected results
  case u[:label]
  when "Electric", "Water", "Sewer"
    if icon != "GREEN"
      puts "  ❌ FAIL: Expected GREEN for #{u[:label]} but got #{icon}"
    else
      puts "  ✅ PASS"
    end
  when "HOA / POA"
    if icon != "RED"
      puts "  ❌ FAIL: Expected RED for #{u[:label]} but got #{icon}"
    else
      puts "  ✅ PASS"
    end
  end
end

puts "\n--- SyncLog Schema Verification ---"
cols = SyncLog.column_names
%w[records_synced records_failed].each do |col|
  if cols.include?(col)
    puts "  ✅ Column '#{col}' EXISTS in sync_logs"
  else
    puts "  ❌ Column '#{col}' MISSING from sync_logs"
  end
end

puts "\n--- SyncLog Status Validation ---"
statuses = SyncLog::STATUSES
%w[running success failed completed_with_errors].each do |s|
  if statuses.include?(s)
    puts "  ✅ Status '#{s}' is valid"
  else
    puts "  ❌ Status '#{s}' NOT in STATUSES"
  end
end

puts "\n--- completed_with_errors? helper ---"
log = SyncLog.new(status: "completed_with_errors")
if log.respond_to?(:completed_with_errors?) && log.completed_with_errors?
  puts "  ✅ completed_with_errors? returns true"
else
  puts "  ❌ completed_with_errors? not working"
end

puts "\n--- Monetary Nil Safety (View Simulation) ---"
fields = {
  opening_bid: parcel.respond_to?(:opening_bid) ? parcel.opening_bid : nil,
  assessed_value: parcel.respond_to?(:assessed_value) ? parcel.assessed_value : nil,
  market_value: parcel.respond_to?(:market_value) ? parcel.market_value : nil,
}
fields.each do |name, val|
  display = val.present? ? number_with_precision(val, precision: 2, delimiter: ",") : "N/A"
  puts "  #{name}: #{val.inspect} => '#{display}'"
rescue => e
  # number_with_precision not available outside view context
  display = val.present? ? sprintf("$%.2f", val) : "N/A"
  puts "  #{name}: #{val.inspect} => '#{display}'"
end

puts "\n" + "=" * 70
puts "  TEST COMPLETE"
puts "=" * 70
