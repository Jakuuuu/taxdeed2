# frozen_string_literal: true

# QA del sistema GIS local (poligonos de parcela) — verificacion offline.
#
# Ejecutar con:
#   bin/rails runner test/scripts/local_gis_qa.rb
#
# Cubre, sin tocar la red:
#   1. Registry poblado y bien tipado
#   2. Alineamiento seeds <-> registry (cada county sembrado tiene polygon)
#   3. STATE_ABBREVIATIONS resuelve correctamente
#   4. compute_cache_ttl entrega TTLs correctos por escenario
#   5. Ruta /api/local_gis/parcel_geometry existe y apunta al controller
#
# Para healthcheck CON red contra los servidores ArcGIS, usar:
#   bin/rake gis:validate_registry

require "json"

failures = []
def check(label, condition, failures, detail: nil)
  if condition
    puts "  [OK]   #{label}"
  else
    puts "  [FAIL] #{label}#{detail ? " — #{detail}" : ""}"
    failures << label
  end
end

puts "\n=== 1. Registry poblado ==="
registry = Api::LocalGisController::COUNTY_GIS_REGISTRY
check("Registry no vacio", registry.any?, failures)
check("Registry congelado (frozen)", registry.frozen?, failures)
registry.each do |key, config|
  check("#{key}: tiene :url", config[:url].is_a?(String) && config[:url].start_with?("http"), failures)
  check("#{key}: tiene :out_fields", config[:out_fields].is_a?(String) && config[:out_fields].present?, failures)
  check("#{key}: clave UPPERCASE", key == key.upcase, failures)
  check("#{key}: clave usa pipe separator", key.include?("|"), failures)
end

puts "\n=== 2. Alineamiento seeds <-> registry ==="
seed_pairs = Auction.distinct.pluck(:county, :state).map { |c, s| "#{c.upcase}|#{s.upcase}" }.sort
registry_keys = registry.keys.sort
puts "  seeds:    #{seed_pairs.join(', ')}"
puts "  registry: #{registry_keys.join(', ')}"

uncovered = seed_pairs - registry_keys
unused    = registry_keys - seed_pairs
check("Todos los counties sembrados estan en el registry",
      uncovered.empty?, failures, detail: uncovered.join(', '))
if unused.any?
  puts "  [INFO] registry sin seeds (no es error): #{unused.join(', ')}"
end

puts "\n=== 3. STATE_ABBREVIATIONS ==="
abbr = Api::LocalGisController::STATE_ABBREVIATIONS
check("'FLORIDA' -> 'FL'",   abbr["FLORIDA"]   == "FL", failures)
check("'GEORGIA' -> 'GA'",   abbr["GEORGIA"]   == "GA", failures)
check("'TEXAS' -> 'TX'",     abbr["TEXAS"]     == "TX", failures)
check("Cubre 50 estados + DC", abbr.size >= 51, failures, detail: "size=#{abbr.size}")

puts "\n=== 4. compute_cache_ttl ==="
controller = Api::LocalGisController.new
default_ttl = Api::LocalGisController::DEFAULT_CACHE_TTL

ttl_blank   = controller.send(:compute_cache_ttl, nil)
check("nil auction_date -> DEFAULT_CACHE_TTL (90 dias)",
      ttl_blank == default_ttl, failures, detail: ttl_blank.inspect)

ttl_invalid = controller.send(:compute_cache_ttl, "not-a-date")
check("fecha invalida -> DEFAULT_CACHE_TTL",
      ttl_invalid == default_ttl, failures, detail: ttl_invalid.inspect)

ttl_past    = controller.send(:compute_cache_ttl, (Date.today - 30).to_s)
check("fecha pasada -> floor 1 hora",
      ttl_past >= 1.hour && ttl_past <= 2.hours, failures, detail: ttl_past.inspect)

ttl_future  = controller.send(:compute_cache_ttl, (Date.today + 10).to_s)
check("fecha futura -> entre 10 y 12 dias",
      ttl_future >= 10.days && ttl_future <= 12.days, failures, detail: ttl_future.inspect)

puts "\n=== 5. Ruta API ==="
route = Rails.application.routes.routes.find do |r|
  r.path.spec.to_s.include?("local_gis/parcel_geometry")
end
check("Ruta /api/local_gis/parcel_geometry existe", route.present?, failures)
if route
  controller_name = route.defaults[:controller]
  action_name     = route.defaults[:action]
  check("Apunta a api/local_gis#parcel_geometry",
        controller_name == "api/local_gis" && action_name == "parcel_geometry",
        failures, detail: "#{controller_name}##{action_name}")
end

puts "\n=== Resumen ==="
if failures.empty?
  puts "  TODO PASA — #{registry.size} condados, registry alineado con seeds, TTL OK, ruta OK"
  exit 0
else
  puts "  #{failures.size} FAIL(s):"
  failures.each { |f| puts "    - #{f}" }
  exit 1
end
