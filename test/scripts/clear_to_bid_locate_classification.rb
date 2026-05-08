#!/usr/bin/env ruby
# frozen_string_literal: true
# Localiza dónde vive la clasificación deficiente/viable/optimo en el Sheet real

def idx_to_col(n)
  s = +""
  n2 = n
  loop do
    s.prepend(((n2 % 26) + 65).chr)
    n2 = n2 / 26 - 1
    break if n2 < 0
  end
  s
end

puts "=" * 70
puts "  CLEAR-TO-BID — LOCALIZACIÓN DE CLASIFICACIÓN en Sheet real"
puts "=" * 70

data = GoogleSheetsImporter.fetch_headers_and_rows(ENV["GOOGLE_SHEET_ID"])
headers = data[:headers]
rows = data[:rows]

puts "\n[Sheet] Headers totales: #{headers.size}"
puts "[Sheet] Filas totales: #{rows.size}"

# 1) Headers candidatos por palabra clave
puts "\n[1] Headers candidatos (búsqueda por keyword):"
keywords = /nota|note|comment|estatus|status|clasif|grade|categori|análi|analy/i
candidates = []
headers.each_with_index do |h, idx|
  next if h.to_s.strip.empty?
  if h.to_s.match?(keywords)
    puts "    [#{idx_to_col(idx)}/idx=#{idx}] #{h.inspect}"
    candidates << idx
  end
end

# 2) Distribución de valores en cada candidato (todas las filas)
puts "\n[2] Valores únicos en candidatos (todas las #{rows.size} filas):"
candidates.each do |idx|
  vals = rows.map { |r| r[idx].to_s.strip }.reject(&:empty?)
  unique = vals.tally.sort_by { |_, v| -v }.first(15)
  puts "\n    Col [#{idx_to_col(idx)}/idx=#{idx}] '#{headers[idx]}' — #{vals.size} no-vacíos / #{vals.uniq.size} únicos:"
  if unique.empty?
    puts "       (sin valores)"
  else
    unique.each { |v, c| puts "       #{c.to_s.rjust(4)}x #{v.inspect[0..80]}" }
  end
end

# 3) Búsqueda exhaustiva por valores: cualquier columna con deficiente/viable/optimo
puts "\n[3] Búsqueda exhaustiva: ¿qué columnas contienen 'deficiente|viable|optimo'?"
target_re = /deficiente|deficient|\bviable\b|\boptimo\b|\bóptimo\b|premium|aceptable/i
hits_per_col = Hash.new { |h, k| h[k] = Hash.new(0) }
rows.each do |r|
  r.each_with_index do |v, idx|
    next if v.to_s.strip.empty?
    if v.to_s.match?(target_re)
      hits_per_col[idx][v.to_s.strip.downcase] += 1
    end
  end
end

if hits_per_col.empty?
  puts "    NINGUNA columna contiene esos valores. La clasificación NO existe aún en el Sheet."
else
  hits_per_col.sort_by { |idx, _| idx }.each do |idx, vals|
    header_label = headers[idx].to_s
    puts "    Col [#{idx_to_col(idx)}/idx=#{idx}] '#{header_label}' — #{vals.values.sum} matches:"
    vals.sort_by { |_, c| -c }.first(10).each do |v, c|
      puts "       #{c.to_s.rjust(4)}x #{v.inspect[0..80]}"
    end
  end
end

# 4) Mostrar todos los headers (para que el usuario vea la estructura completa)
puts "\n[4] Mapa completo del Sheet (idx → header):"
headers.each_with_index do |h, idx|
  next if h.to_s.strip.empty?
  marker = candidates.include?(idx) ? "  ←──candidate" : ""
  marker = "  ←──HAS CLASSIFICATION" if hits_per_col.key?(idx)
  puts "    [#{idx_to_col(idx).rjust(3)}/#{idx.to_s.rjust(3)}] #{h.inspect}#{marker}"
end

puts "\n" + "=" * 70
