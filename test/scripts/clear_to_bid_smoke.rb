#!/usr/bin/env ruby
# frozen_string_literal: true
# Smoke test end-to-end de Rama 6 — Clear-to-Bid
# Uso: bundle exec rails runner test/scripts/clear_to_bid_smoke.rb

require "ostruct"

passed = 0
failed = 0
def check(label, ok)
  print "  #{ok ? "✅" : "❌"} #{label}\n"
  ok
end

puts "=" * 60
puts "  CLEAR-TO-BID — SMOKE TEST end-to-end"
puts "=" * 60

# ── 1) Schema ────────────────────────────────────────────────────────────────
puts "\n[1] Schema (parcels)"
%w[clear_to_bid_grade clear_to_bid_grade_locked polygon_encoded].each do |col|
  check("parcels.#{col}", Parcel.column_names.include?(col)) ? passed += 1 : failed += 1
end

# ── 2) Model API ─────────────────────────────────────────────────────────────
puts "\n[2] Model API"
check("Parcel::CLEAR_TO_BID_GRADES is %w[deficiente viable optimo]",
      Parcel::CLEAR_TO_BID_GRADES == %w[deficiente viable optimo]) ? passed += 1 : failed += 1
check("Parcel.clear_to_bid scope filters by grade IN (viable,optimo)",
      Parcel.clear_to_bid.to_sql.include?("clear_to_bid_grade")) ? passed += 1 : failed += 1
check("Subscription#premier_active? defined",
      Subscription.instance_methods.include?(:premier_active?)) ? passed += 1 : failed += 1

# ── 3) Polyline encoder (Google reference) ──────────────────────────────────
puts "\n[3] Polyline encoder"
ring = [[38.5, -120.2], [40.7, -120.95], [43.252, -126.453]]
encoded = ParcelPolygonEncoder::Polyline.encode(ring)
expected = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
check("Google reference vector matches", encoded == expected) ? passed += 1 : failed += 1
puts "      got      = #{encoded.inspect}"
puts "      expected = #{expected.inspect}"

# ── 4) Static Map helper ─────────────────────────────────────────────────────
puts "\n[4] Static Map helper"
helper = Class.new { include ClearToBidHelper }.new
no_poly = OpenStruct.new(latitude: 25.7617, longitude: -80.1918, polygon_encoded: nil)
url1 = helper.static_map_url(no_poly).to_s
check("Marker fallback URL contains 'markers='", url1.include?("markers=")) ? passed += 1 : failed += 1
check("Marker URL contains 'key='", url1.include?("key=")) ? passed += 1 : failed += 1

with_poly = OpenStruct.new(latitude: 25.7617, longitude: -80.1918, polygon_encoded: encoded)
url2 = helper.static_map_url(with_poly).to_s
check("Polygon URL contains 'path=' (or url-encoded)",
      url2.include?("path=") || url2.include?("path%3D")) ? passed += 1 : failed += 1
check("Polygon URL contains 'enc' (path or URL-encoded)",
      url2.match?(/enc[%:]/)) ? passed += 1 : failed += 1
check("Polygon URL contains 'E67E22' (regla naranja stroke)",
      url2.upcase.include?("E67E22")) ? passed += 1 : failed += 1

# ── 5) Routes ────────────────────────────────────────────────────────────────
puts "\n[5] Routes"
helpers = Rails.application.routes.url_helpers
check("research_clear_to_bid_path → /research/clear_to_bid",
      helpers.research_clear_to_bid_path == "/research/clear_to_bid") ? passed += 1 : failed += 1
check("admin_parcels_path → /admin/parcels",
      helpers.admin_parcels_path == "/admin/parcels") ? passed += 1 : failed += 1

# ── 6) Sheet → Grade derivation ─────────────────────────────────────────────
puts "\n[6] Sheet col F → grade derivation"
processor = SheetRowProcessor.send(:new, [], auction_cache: nil, row_hyperlinks: nil)
samples = {
  "Optimo"     => "optimo",
  "OPTIMO"     => "optimo",
  "Óptimo"=> "optimo",  # Óptimo
  "viable"     => "viable",
  "Deficiente" => "deficiente",
  "no viable"  => "deficiente",
  "bogus"      => nil,
  ""           => nil,
  nil          => nil
}
samples.each do |raw, want|
  got = processor.send(:derive_clear_to_bid_grade, raw)
  check("derive(#{raw.inspect}) → #{want.inspect} (got #{got.inspect})", got == want) ? passed += 1 : failed += 1
end

# ── 7) CRM Immunity ──────────────────────────────────────────────────────────
puts "\n[7] CRM Immunity"
expected_cols = %w[parcel_user_tags parcel_user_notes parcel_watches user_tags user_notes]
check("CRM_IMMUNE_COLUMNS unchanged",
      SheetRowProcessor::CRM_IMMUNE_COLUMNS.sort == expected_cols.sort) ? passed += 1 : failed += 1

# ── 8) Payload concern shape ─────────────────────────────────────────────────
puts "\n[8] ClearToBidPayload concern"
ctx = Class.new { include ClearToBidPayload }.new
fake_parcels = [OpenStruct.new(id: 1, state: "FL", county: "Miami-Dade", clear_to_bid_grade: "viable")]
skel = ctx.clear_to_bid_skeleton(fake_parcels).first
forbidden_keys = %i[address parcel_id latitude longitude opening_bid]
leaked = forbidden_keys.select { |k| skel.key?(k) }
check("Skeleton payload omits #{forbidden_keys.inspect}",
      leaked.empty?) ? passed += 1 : failed += 1
puts "      skeleton keys = #{skel.keys.sort.inspect}"

# ── Result ──────────────────────────────────────────────────────────────────
puts
puts "=" * 60
puts "  PASSED: #{passed}    FAILED: #{failed}"
puts "=" * 60
exit(failed.zero? ? 0 : 1)
