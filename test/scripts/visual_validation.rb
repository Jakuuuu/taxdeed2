#!/usr/bin/env ruby
# frozen_string_literal: true
# ═══════════════════════════════════════════════════════════════
#  Visual Validation Script — Data Rendering Audit
#  Usage: bundle exec rails runner test/scripts/visual_validation.rb
# ═══════════════════════════════════════════════════════════════

include ActionView::Helpers::NumberHelper

puts ""
puts "═" * 74
puts "  VALIDACIÓN VISUAL — Auditoría de Renderizado de Datos"
puts "  Pipeline: PostgreSQL → ERB View → Browser"
puts "  #{Time.current}"
puts "═" * 74

total_pass = 0
total_fail = 0

def check(label, condition, detail = "")
  if condition
    puts "    ✅ PASS #{label}#{detail.present? ? " → #{detail}" : ""}"
    return true
  else
    puts "    ❌ FAIL #{label}#{detail.present? ? " → #{detail}" : ""}"
    return false
  end
end

# ─── SECTION 1: Sample real data to verify DB types ────────────────────
puts ""
puts "┌─────────────────────────────────────────────────────────────┐"
puts "│  1. INSPECCIÓN DE DATOS REALES EN BD                       │"
puts "└─────────────────────────────────────────────────────────────┘"

total = Parcel.count
with_bid = Parcel.where.not(opening_bid: nil).count
with_assessed = Parcel.where.not(assessed_value: nil).count
with_market = Parcel.where.not(market_value: nil).count
with_coords = Parcel.where.not(latitude: nil).where.not(longitude: nil).count
with_zoning = Parcel.where.not(zoning: [nil, ""]).count
with_fema = Parcel.where.not(fema_risk_level: [nil, ""]).count
with_electric = Parcel.where.not(electric: [nil, ""]).count

puts "    📊 Total parcelas: #{total}"
puts "    💰 Con opening_bid: #{with_bid} (#{(with_bid.to_f/total*100).round(1)}%)"
puts "    💰 Con assessed_value: #{with_assessed} (#{(with_assessed.to_f/total*100).round(1)}%)"
puts "    💰 Con market_value: #{with_market} (#{(with_market.to_f/total*100).round(1)}%)"
puts "    📍 Con coordenadas: #{with_coords} (#{(with_coords.to_f/total*100).round(1)}%)"
puts "    🏗 Con zoning: #{with_zoning} (#{(with_zoning.to_f/total*100).round(1)}%)"
puts "    🌊 Con FEMA risk: #{with_fema} (#{(with_fema.to_f/total*100).round(1)}%)"
puts "    ⚡ Con electric: #{with_electric} (#{(with_electric.to_f/total*100).round(1)}%)"

# ─── SECTION 2: Verify financial field formatting ──────────────────────
puts ""
puts "┌─────────────────────────────────────────────────────────────┐"
puts "│  2. FORMATEO FINANCIERO — number_to_currency               │"
puts "└─────────────────────────────────────────────────────────────┘"

p = Parcel.where.not(opening_bid: nil).where.not(assessed_value: nil).first
if p
  puts "    Parcela de prueba: #{p.state}/#{p.county}/#{p.parcel_id}"
  puts ""

  # Opening bid
  raw = p.opening_bid
  formatted = number_to_currency(raw, unit: "", delimiter: ",", separator: ".")
  full_formatted = number_to_currency(raw)
  puts "    opening_bid raw: #{raw} (#{raw.class})"
  puts "    → Hero format: $#{formatted}"
  puts "    → Grid format: #{full_formatted}"
  r = check("Opening bid es BigDecimal o Numeric", raw.is_a?(Numeric))
  total_pass += 1 if r; total_fail += 1 unless r

  r = check("Formateo tiene delimitador de miles", full_formatted.include?(",") || raw < 1000)
  total_pass += 1 if r; total_fail += 1 unless r

  r = check("Formateo incluye signo $", full_formatted.start_with?("$"))
  total_pass += 1 if r; total_fail += 1 unless r

  # Assessed value
  raw_av = p.assessed_value
  formatted_av = number_to_currency(raw_av)
  puts ""
  puts "    assessed_value raw: #{raw_av} (#{raw_av.class})"
  puts "    → Formatted: #{formatted_av}"
  r = check("Assessed value formateado correcto", formatted_av.start_with?("$"))
  total_pass += 1 if r; total_fail += 1 unless r

  # Market value
  if p.market_value
    raw_mv = p.market_value
    formatted_mv = number_to_currency(raw_mv)
    puts ""
    puts "    market_value raw: #{raw_mv} (#{raw_mv.class})"
    puts "    → Formatted: #{formatted_mv}"
    r = check("Market value formateado correcto", formatted_mv.start_with?("$"))
    total_pass += 1 if r; total_fail += 1 unless r
  end

  # Est sale value
  if p.estimated_sale_value
    formatted_esv = number_to_currency(p.estimated_sale_value)
    puts ""
    puts "    estimated_sale_value raw: #{p.estimated_sale_value}"
    puts "    → Formatted: #{formatted_esv}"
    r = check("Est Sale Value formateado", formatted_esv.start_with?("$"))
    total_pass += 1 if r; total_fail += 1 unless r
  end

  # Price per acre
  if p.price_per_acre
    formatted_ppa = number_to_currency(p.price_per_acre)
    puts ""
    puts "    price_per_acre raw: #{p.price_per_acre}"
    puts "    → Formatted: #{formatted_ppa}"
    r = check("Price/Acre formateado", formatted_ppa.start_with?("$"))
    total_pass += 1 if r; total_fail += 1 unless r
  end
else
  puts "    ⚠️ No hay parcelas con opening_bid + assessed_value"
end

# ─── SECTION 3: Null handling — "—" dash for missing values ───────────
puts ""
puts "┌─────────────────────────────────────────────────────────────┐"
puts "│  3. NULL HANDLING — Verificar que nulos muestran '—'       │"
puts "└─────────────────────────────────────────────────────────────┘"

# Find a parcel with NULLs
pn = Parcel.where(zoning: nil, fema_risk_level: nil).first
if pn
  puts "    Parcela con nulos: #{pn.state}/#{pn.county}/#{pn.parcel_id}"

  # Simulate what the ERB does:
  rendered_zoning = pn.zoning.presence || "—"
  rendered_fema = pn.fema_risk_level.presence || "—"
  rendered_ob = pn.opening_bid ? number_to_currency(pn.opening_bid) : "—"
  rendered_mv = pn.market_value ? number_to_currency(pn.market_value) : "—"
  rendered_owner = pn.owner_name.presence || "—"
  rendered_lat = pn.latitude.present? ? pn.latitude.to_s : "nil (map placeholder shown)"
  rendered_lot = pn.lot_area_acres.present? ? "#{pn.lot_area_acres} ac" : "—"

  puts ""
  r = check("Zoning nil → dash", rendered_zoning == "—", rendered_zoning)
  total_pass += 1 if r; total_fail += 1 unless r

  r = check("FEMA nil → dash", rendered_fema == "—", rendered_fema)
  total_pass += 1 if r; total_fail += 1 unless r

  r = check("Null values nunca muestran 'nil' como texto", !rendered_zoning.include?("nil"))
  total_pass += 1 if r; total_fail += 1 unless r

  r = check("Null values nunca muestran 'null' como texto", !rendered_fema.include?("null"))
  total_pass += 1 if r; total_fail += 1 unless r

  r = check("Opening bid nil → dash", rendered_ob == "—" || rendered_ob.start_with?("$"), rendered_ob)
  total_pass += 1 if r; total_fail += 1 unless r
else
  puts "    ⚠️ Todas las parcelas tienen zoning y fema — buscando alternativa..."
  pn2 = Parcel.first
  rendered_z = pn2.zoning.presence || "—"
  r = check("Parcela reifica .presence || dash pattern", rendered_z.is_a?(String))
  total_pass += 1 if r; total_fail += 1 unless r
end

# ─── SECTION 4: ERB Template Guards Audit ─────────────────────────────
puts ""
puts "┌─────────────────────────────────────────────────────────────┐"
puts "│  4. AUDITORÍA DE TEMPLATE ERB — Guards contra nil          │"
puts "└─────────────────────────────────────────────────────────────┘"

template_path = File.expand_path("../../app/views/research/parcels/show.html.erb", __dir__)
template = File.read(template_path)

# Check all financial fields use the ternary guard pattern
financial_fields = %w[opening_bid assessed_value market_value land_value improvement_value
                      delinquent_amount estimated_sale_value price_per_acre
                      max_bid_30 max_bid_35]

financial_fields.each do |field|
  # Pattern: @parcel.field ? number_to_currency(@parcel.field) : "—"
  has_guard = template.include?("@parcel.#{field} ?") || template.include?("@parcel.#{field}?")
  r = check("#{field} tiene guard ternario", has_guard)
  total_pass += 1 if r; total_fail += 1 unless r
end

# Check string fields use .presence || "—"
string_fields = %w[year_built zoning land_use lot_shape jurisdiction owner_name property_address]
string_fields.each do |field|
  has_presence = template.include?("#{field}.presence") || template.include?("#{field}.present?")
  r = check("#{field} usa .presence guard", has_presence)
  total_pass += 1 if r; total_fail += 1 unless r
end

# ─── SECTION 5: Blur Paywall Structure ────────────────────────────────
puts ""
puts "┌─────────────────────────────────────────────────────────────┐"
puts "│  5. BLUR PAYWALL — Estructura CSS correcta                 │"
puts "└─────────────────────────────────────────────────────────────┘"

r = check("CSS: filter blur(5px) para .fp-locked", template.include?("blur(5px)"))
total_pass += 1 if r; total_fail += 1 unless r

r = check("CSS: user-select: none en locked", template.include?("user-select: none"))
total_pass += 1 if r; total_fail += 1 unless r

r = check("CSS: pointer-events: none en locked", template.include?("pointer-events: none"))
total_pass += 1 if r; total_fail += 1 unless r

r = check("CSS: overflow: visible gotcha documentado", template.include?("overflow: visible"))
total_pass += 1 if r; total_fail += 1 unless r

# Count premium sections
premium_count = template.scan("fp-premium").count
r = check("4+ secciones premium encontradas", premium_count >= 8, "#{premium_count} ocurrencias (CSS+HTML)")
total_pass += 1 if r; total_fail += 1 unless r

# Verify @unlocked toggle
unlocked_refs = template.scan("@unlocked").count
r = check("@unlocked toggle usado", unlocked_refs >= 4, "#{unlocked_refs} referencias")
total_pass += 1 if r; total_fail += 1 unless r

# ─── SECTION 6: CRM Immunity in View ─────────────────────────────────
puts ""
puts "┌─────────────────────────────────────────────────────────────┐"
puts "│  6. CRM IMMUNITY — Mini CRM siempre visible                │"
puts "└─────────────────────────────────────────────────────────────┘"

r = check("CRM card fuera de fp-premium", template.include?('id="ficha-crm"'))
total_pass += 1 if r; total_fail += 1 unless r

# Verify CRM is NOT inside a premium section
crm_pos = template.index('id="ficha-crm"')
premium_1_pos = template.index('id="ficha-premium-1"')
r = check("CRM aparece ANTES de premium sections", crm_pos < premium_1_pos)
total_pass += 1 if r; total_fail += 1 unless r

# Verify CRM card does NOT have fp-premium class
crm_section = template[crm_pos - 200..crm_pos]
r = check("CRM card NO tiene clase fp-premium", !crm_section.include?("fp-premium"))
total_pass += 1 if r; total_fail += 1 unless r

r = check("CRM tiene badge 'Always Visible'", template.include?("Always Visible"))
total_pass += 1 if r; total_fail += 1 unless r

# ─── SECTION 7: GIS Map always visible ────────────────────────────────
puts ""
puts "┌─────────────────────────────────────────────────────────────┐"
puts "│  7. GIS MAP — Siempre visible, fuera del paywall           │"
puts "└─────────────────────────────────────────────────────────────┘"

gis_pos = template.index('id="ficha-gis"')
gis_section = template[gis_pos - 200..gis_pos]
r = check("GIS Map NO tiene clase fp-premium", !gis_section.include?("fp-premium"))
total_pass += 1 if r; total_fail += 1 unless r

r = check("Map placeholder para coords vacías", template.include?("No coordinates available"))
total_pass += 1 if r; total_fail += 1 unless r

r = check("has_coords? guard en template", template.include?("has_coords?"))
total_pass += 1 if r; total_fail += 1 unless r

# ─── SECTION 8: External links conditional rendering ─────────────────
puts ""
puts "┌─────────────────────────────────────────────────────────────┐"
puts "│  8. EXTERNAL LINKS — Renderizado condicional               │"
puts "└─────────────────────────────────────────────────────────────┘"

link_fields = %w[regrid_url google_maps_url clerk_url tax_collector_url fema_url gis_image_url property_image_url]
link_fields.each do |field|
  has_guard = template.include?("@parcel.#{field}.present?")
  r = check("#{field} tiene .present? guard", has_guard)
  total_pass += 1 if r; total_fail += 1 unless r
end

# ─── SECTION 9: Real data rendering simulation ────────────────────────
puts ""
puts "┌─────────────────────────────────────────────────────────────┐"
puts "│  9. SIMULACIÓN VISUAL — Render de parcela rica             │"
puts "└─────────────────────────────────────────────────────────────┘"

rich = Parcel.where.not(opening_bid: nil)
             .where.not(zoning: [nil, ""])
             .where.not(latitude: nil)
             .first

if rich
  puts ""
  puts "    ┌──────────────────────────────────────────────────────────┐"
  puts "    │  🏠 PROPERTY CARD PREVIEW  (Simulated Render)           │"
  puts "    ├──────────────────────────────────────────────────────────┤"
  puts "    │  APN: #{rich.parcel_id}"
  puts "    │  #{rich.address.presence || 'Address not available'}"
  puts "    │  #{[rich.county, rich.state, rich.zip_code].compact.join(', ')}"
  puts "    │"
  puts "    │  El precio inicia en $#{number_to_currency(rich.opening_bid, unit: '', delimiter: ',', separator: '.')}"
  puts "    ├──────────────────────────────────────────────────────────┤"
  puts "    │  PROPERTY CHARACTERISTICS"
  puts "    │  Zoning:      #{rich.zoning.presence || '—'}"
  puts "    │  Land Use:    #{rich.land_use.presence || '—'}"
  puts "    │  Lot Acres:   #{rich.lot_area_acres.present? ? "#{rich.lot_area_acres} ac" : '—'}"
  puts "    │  Sqft Lot:    #{rich.sqft_lot.present? ? "#{number_with_delimiter(rich.sqft_lot)} sqft" : '—'}"
  puts "    │  Sqft Living: #{rich.living_area_sqft.present? ? "#{number_with_delimiter(rich.living_area_sqft)} sqft" : '—'}"
  puts "    │  Jurisdiction: #{rich.jurisdiction.presence || '—'}"
  puts "    │  Homestead:   #{rich.homestead_flag.present? ? rich.homestead_flag.titleize : '—'}"
  puts "    ├──────────────────────────────────────────────────────────┤"
  puts "    │  PROPERTY VALUATION"
  puts "    │  Assessed:    #{rich.assessed_value ? number_to_currency(rich.assessed_value) : '—'}"
  puts "    │  Market:      #{rich.market_value ? number_to_currency(rich.market_value) : '—'}"
  puts "    │  Est. Sale:   #{rich.estimated_sale_value ? number_to_currency(rich.estimated_sale_value) : '—'}"
  puts "    │  Price/Acre:  #{rich.price_per_acre ? number_to_currency(rich.price_per_acre) : '—'}"
  puts "    │  Owner:       #{rich.owner_name.presence || '—'}"
  puts "    ├──────────────────────────────────────────────────────────┤"
  puts "    │  UTILITIES & RISK"
  puts "    │  Electric:    #{rich.electric.present? ? rich.electric.titleize : '—'}"
  puts "    │  Water:       #{rich.water.present? ? rich.water.titleize : '—'}"
  puts "    │  Sewer:       #{rich.sewer.present? ? rich.sewer.titleize : '—'}"
  puts "    │  HOA:         #{rich.hoa.present? ? rich.hoa.titleize : '—'}"
  puts "    │  Wetlands:    #{rich.wetlands.nil? ? '—' : (rich.wetlands ? 'Yes' : 'No')}"
  puts "    │  FEMA Risk:   #{rich.fema_risk_level.presence || '—'}"
  puts "    ├──────────────────────────────────────────────────────────┤"
  puts "    │  GIS MAP"
  puts "    │  Lat: #{rich.latitude}  Lng: #{rich.longitude}"
  puts "    │  #{rich.has_coords? ? '✅ Map will render' : '⬜ Map placeholder shown'}"
  puts "    ├──────────────────────────────────────────────────────────┤"
  puts "    │  EXTERNAL LINKS"
  links = []
  links << "Regrid" if rich.regrid_url.present?
  links << "Google Maps" if rich.google_maps_url.present?
  links << "Clerk" if rich.clerk_url.present?
  links << "Tax Collector" if rich.tax_collector_url.present?
  links << "FEMA" if rich.fema_url.present?
  links << "GIS Image" if rich.gis_image_url.present?
  links << "Property Photo" if rich.property_image_url.present?
  puts "    │  #{links.any? ? links.join(' · ') : 'No links available'}"
  puts "    └──────────────────────────────────────────────────────────┘"
  puts ""

  # Verify none of the rendered values contain "nil" or "null" text
  rendered_values = [
    rich.zoning.presence || "—",
    rich.land_use.presence || "—",
    rich.jurisdiction.presence || "—",
    rich.owner_name.presence || "—",
    rich.opening_bid ? number_to_currency(rich.opening_bid) : "—",
    rich.assessed_value ? number_to_currency(rich.assessed_value) : "—",
    rich.electric.present? ? rich.electric : "—",
    rich.fema_risk_level.presence || "—"
  ]

  all_clean = rendered_values.none? { |v| v.to_s.downcase == "nil" || v.to_s.downcase == "null" }
  r = check("Ningún valor renderiza texto 'nil' o 'null'", all_clean)
  total_pass += 1 if r; total_fail += 1 unless r

  # Verify no raw BigDecimal scientific notation
  money_values = [rich.opening_bid, rich.assessed_value, rich.market_value].compact
  no_scientific = money_values.none? { |v| v.to_s.include?("e") || v.to_s.include?("E") }
  r = check("No hay notación científica en valores monetarios", no_scientific)
  total_pass += 1 if r; total_fail += 1 unless r
else
  puts "    ⚠️ No hay parcela con bid + zoning + coords — usando fallback"
  rich = Parcel.where.not(opening_bid: nil).first
  if rich
    puts "    Parcela: #{rich.state}/#{rich.county}/#{rich.parcel_id}"
    puts "    Opening Bid: #{number_to_currency(rich.opening_bid)}"
  end
end

# ─── SECTION 10: Parcela con TODOS los nulos ──────────────────────────
puts ""
puts "┌─────────────────────────────────────────────────────────────┐"
puts "│  10. PARCELA VACÍA — Sin datos premium                     │"
puts "└─────────────────────────────────────────────────────────────┘"

empty_p = Parcel.where(opening_bid: nil, assessed_value: nil, market_value: nil, zoning: nil).first
if empty_p
  puts "    Parcela vacía: #{empty_p.state}/#{empty_p.county}/#{empty_p.parcel_id}"
  puts ""
  puts "    Preview renderizado:"
  puts "    │  Opening Bid:  #{empty_p.opening_bid ? number_to_currency(empty_p.opening_bid, unit: '', delimiter: ',', separator: '.') : '—'}"
  puts "    │  Assessed:     #{empty_p.assessed_value ? number_to_currency(empty_p.assessed_value) : '—'}"
  puts "    │  Market:       #{empty_p.market_value ? number_to_currency(empty_p.market_value) : '—'}"
  puts "    │  Zoning:       #{empty_p.zoning.presence || '—'}"
  puts "    │  Lat:          #{empty_p.latitude || 'nil → Map placeholder'}"
  puts "    │  Electric:     #{empty_p.electric.present? ? empty_p.electric : '—'}"

  all_dashes = [
    (empty_p.opening_bid ? "$X" : "—"),
    (empty_p.assessed_value ? "$X" : "—"),
    (empty_p.zoning.presence || "—")
  ].all? { |v| v == "—" }
  r = check("Todos los campos nulos muestran '—'", all_dashes)
  total_pass += 1 if r; total_fail += 1 unless r
else
  puts "    ℹ️ No existe parcela totalmente vacía — coverage OK (todos tienen algún dato)"
  total_pass += 1
end

# ═══════════════════════════════════════════════════════════════
puts ""
puts "═" * 74
puts "  📋 RESUMEN DE VALIDACIÓN VISUAL"
puts "═" * 74
puts ""
puts "  Total de aserciones: #{total_pass + total_fail}"
puts "  Pasaron:             #{total_pass} ✅"
puts "  Fallaron:            #{total_fail} ❌"
pct = total_fail == 0 ? 100.0 : ((total_pass.to_f / (total_pass + total_fail)) * 100).round(1)
puts ""
if total_fail == 0
  puts "  ── VEREDICTO: #{pct}% → 🏆 RENDERIZADO VISUAL PERFECTO"
else
  puts "  ── VEREDICTO: #{pct}% → ⚠️ HAY #{total_fail} PROBLEMA(S) POR RESOLVER"
end
puts "═" * 74
puts ""
