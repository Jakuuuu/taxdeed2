# frozen_string_literal: true
# Validación Visual de la Auditoría de Integridad
# Ejecutar: rails runner test/scripts/visual_audit.rb

puts
puts "=" * 70
puts "  🔍 VALIDACIÓN VISUAL — Auditoría de Integridad de Parcels"
puts "  #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}"
puts "=" * 70

# ── 1. Constraints NOT NULL ────────────────────────────────────────────
puts "\n  1️⃣  CONSTRAINTS NOT NULL en PostgreSQL:"
cols = ActiveRecord::Base.connection.columns("parcels")
%w[state county parcel_id].each do |col_name|
  col = cols.find { |c| c.name == col_name }
  status = col.null == false ? "✅ NOT NULL" : "❌ NULLABLE"
  puts "     #{col_name.ljust(12)} → #{status} (type: #{col.sql_type})"
end

# ── 2. UNIQUE INDEX ────────────────────────────────────────────────────
puts "\n  2️⃣  UNIQUE INDEX compuesto:"
indexes = ActiveRecord::Base.connection.indexes("parcels")
idx = indexes.find { |i| i.name == "idx_parcels_unique_state_county_pid" }
if idx
  puts "     ✅ #{idx.name}"
  puts "        columns: #{idx.columns.inspect}"
  puts "        unique:  #{idx.unique}"
else
  puts "     ❌ ÍNDICE NO ENCONTRADO — VULNERABILIDAD CRÍTICA"
end

# ── 3. Validaciones del modelo ─────────────────────────────────────────
puts "\n  3️⃣  Validaciones en app/models/parcel.rb:"
%w[state county parcel_id].each do |attr|
  validators = Parcel.validators_on(attr.to_sym)
  has_presence = validators.any? { |v| v.is_a?(ActiveRecord::Validations::PresenceValidator) }
  status = has_presence ? "✅ presence: true" : "❌ SIN validación presence"
  puts "     #{attr.ljust(12)} → #{status}"
end

# ── 4. Parcelas basura (NULL en identificadores) ───────────────────────
puts "\n  4️⃣  Parcelas con NULL en identificadores (basura):"
# Usando SQL directo para evitar que AR filtre
null_count = ActiveRecord::Base.connection.execute(
  "SELECT COUNT(*) FROM parcels WHERE state IS NULL OR county IS NULL OR parcel_id IS NULL"
).first["count"]
puts "     Registros basura: #{null_count}"
status = null_count.to_i == 0 ? "✅ Base de datos limpia" : "❌ BASURA DETECTADA"
puts "     #{status}"

# ── 5. Duplicados ──────────────────────────────────────────────────────
puts "\n  5️⃣  Duplicados (mismo state+county+parcel_id):"
dupes = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT state, county, parcel_id, COUNT(*) as cnt
  FROM parcels
  GROUP BY state, county, parcel_id
  HAVING COUNT(*) > 1
  LIMIT 10
SQL
if dupes.count == 0
  puts "     ✅ CERO duplicados — Unicidad absoluta"
else
  puts "     ❌ #{dupes.count} grupos duplicados encontrados:"
  dupes.each do |row|
    puts "        #{row['state']}/#{row['county']}/#{row['parcel_id']} → #{row['cnt']}x"
  end
end

# ── 6. Estadísticas generales ──────────────────────────────────────────
puts "\n  6️⃣  Estadísticas generales:"
total = Parcel.count
states = Parcel.distinct.pluck(:state).compact.sort
counties = Parcel.distinct.pluck(:county).compact.count
puts "     Total parcelas:   #{total}"
puts "     Estados únicos:   #{states.count} (#{states.join(', ')})"
puts "     Condados únicos:  #{counties}"

# ── 7. Schema.rb confirma NOT NULL ─────────────────────────────────────
puts "\n  7️⃣  Verificación schema.rb (fuente de verdad de Rails):"
schema = File.read(Rails.root.join("db", "schema.rb"))
%w[state county parcel_id].each do |col_name|
  # Buscar la línea que define la columna en la tabla parcels
  match = schema.match(/create_table "parcels".*?end/m)
  if match
    col_line = match[0].lines.find { |l| l.include?("\"#{col_name}\"") && !l.include?("bigint") }
    if col_line && col_line.include?("null: false")
      puts "     #{col_name.ljust(12)} → ✅ null: false en schema.rb"
    else
      puts "     #{col_name.ljust(12)} → ❌ NO tiene null: false en schema.rb"
    end
  end
end

# ── VEREDICTO ──────────────────────────────────────────────────────────
puts "\n" + "=" * 70

checks = []
checks << (cols.find { |c| c.name == "state" }&.null == false)
checks << (cols.find { |c| c.name == "county" }&.null == false)
checks << (cols.find { |c| c.name == "parcel_id" }&.null == false)
checks << (idx && idx.unique)
checks << Parcel.validators_on(:state).any? { |v| v.is_a?(ActiveRecord::Validations::PresenceValidator) }
checks << (null_count.to_i == 0)
checks << (dupes.count == 0)

if checks.all?
  puts "  🏆 VEREDICTO: #{checks.count}/#{checks.count} verificaciones PASARON"
  puts "     La duplicación de parcelas es MATEMÁTICAMENTE IMPOSIBLE"
else
  failed = checks.count { |c| !c }
  puts "  🚨 VEREDICTO: #{failed} verificación(es) FALLARON"
end
puts "=" * 70
puts
