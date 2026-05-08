#!/usr/bin/env ruby
# frozen_string_literal: true
# Status del mapeo Notas → clear_to_bid_grade en BD real

puts "=" * 70
puts "  CLEAR-TO-BID — STATUS DEL MAPEO en BD"
puts "=" * 70

total = Parcel.count
populated = Parcel.where.not(clear_to_bid_grade: nil).count
nilg = total - populated

puts "\n[BD] Parcels totales: #{total}"
puts "      con clear_to_bid_grade: #{populated}"
puts "      sin clear_to_bid_grade: #{nilg}"

if populated.positive?
  puts "\n[BD] Distribución por grade:"
  Parcel.where.not(clear_to_bid_grade: nil)
        .group(:clear_to_bid_grade)
        .count
        .sort_by { |_, v| -v }
        .each { |g, c| puts "      #{g.ljust(15)} → #{c}" }
end

puts "\n[BD] Locks activos:"
locked = Parcel.where(clear_to_bid_grade_locked: true).count
puts "      clear_to_bid_grade_locked = TRUE: #{locked}"

puts "\n[BD] polygon_encoded poblados:"
poly = Parcel.where.not(polygon_encoded: nil).count
puts "      con polygon_encoded: #{poly}"
puts "      sin polygon_encoded en grade∈{viable,optimo}: #{Parcel.clear_to_bid.where(polygon_encoded: nil).count}"

# ── Sync logs: cuándo fue el último sync, qué dijo del grade ─────────────
puts "\n[Sync history]"
last = SyncLog.order(created_at: :desc).limit(3)
if last.any?
  last.each do |s|
    puts "      #{s.created_at.strftime("%Y-%m-%d %H:%M")} status=#{s.status} added=#{s.parcels_added} updated=#{s.parcels_updated}"
  end
  most_recent = last.first
  migration_ts = Time.zone.parse("2026-05-07 12:00:00")  # migración 20260507120000
  if most_recent.created_at < migration_ts
    puts "\n      ⚠️  Último sync ANTES de la migración → la columna está vacía a propósito."
    puts "          Para poblar: trigger sync nuevo (admin /admin/sync 'Run now' o SyncSheetJob.perform_later)."
  else
    puts "\n      ✅ Sync más reciente fue post-migración → debería haber grades poblados arriba."
  end
else
  puts "      (sin sync_logs registrados)"
end

# ── Sample raw del Sheet col F (sin disparar sync completo) ──────────────
puts "\n[Sheet col F — peek] (consulta pequeña para ver qué texto tiene la columna F)"
begin
  data = GoogleSheetsImporter.fetch_headers_and_rows(ENV["GOOGLE_SHEET_ID"])
  rows = data[:rows].first(20)  # primeras 20 filas
  puts "      Headers col F = #{data[:headers][SheetColumnMap::NOTAS].inspect}"
  notas_sample = rows.map { |r| r[SheetColumnMap::NOTAS] }.compact.reject(&:empty?).uniq.first(15)
  if notas_sample.empty?
    puts "      (col F vacía en las primeras 20 filas)"
  else
    puts "      Valores únicos col F en primeras 20 filas:"
    notas_sample.each do |v|
      mapped = SheetRowProcessor.send(:new, [], auction_cache: nil, row_hyperlinks: nil)
                                .send(:derive_clear_to_bid_grade, v)
      puts "        #{v.inspect.ljust(30)} → #{mapped.inspect}"
    end
  end
rescue StandardError => e
  puts "      (no se pudo consultar Sheet: #{e.class}: #{e.message})"
end

puts
puts "=" * 70
