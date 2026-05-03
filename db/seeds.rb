# seeds.rb — TaxDeed Lion
# Idempotent: uses find_or_create_by! on stable unique keys.
#
# Cobertura GIS: los 6 condados sembrados aqui DEBEN existir en
# Api::LocalGisController::COUNTY_GIS_REGISTRY para que la Ficha de Propiedad
# muestre el poligono. Si agregas un condado nuevo, registralo tambien alli.

puts "=== Seeding Auctions (Tax Deed) ==="

today = Date.today

auctions_data = [
  # ── Florida — Palm Beach ──────────────────────────────────────────
  {
    state:                 "FL",
    county:                "Palm Beach",
    auction_type:          "tax_deed",
    status:                "upcoming",
    sale_date:             today + 18,
    end_date:              today + 18,
    registration_opens:    today - 14,
    registration_deadline: today + 10,
    bidding_start:         today + 17,
    latitude:              26.7153,
    longitude:             -80.0534,
    bidding_url:           "https://palmbeach.realtaxdeed.com",
    source_url:            "https://www.mypalmbeachclerk.com/tax-deeds",
    parcel_count:          132,
    total_amount:          2_850_000.00,
    notes:                 "Online bidding via RealTaxDeed. Deposits required 5 days before sale."
  },
  # ── Florida — Brevard ─────────────────────────────────────────────
  {
    state:                 "FL",
    county:                "Brevard",
    auction_type:          "tax_deed",
    status:                "active",
    sale_date:             today + 3,
    end_date:              today + 3,
    registration_opens:    today - 20,
    registration_deadline: today - 2,
    bidding_start:         today + 2,
    latitude:              28.0836,
    longitude:             -80.6081,
    bidding_url:           "https://brevard.realtaxdeed.com",
    source_url:            "https://www.brevardclerk.us/tax-deeds",
    parcel_count:          87,
    total_amount:          1_940_500.00,
    notes:                 nil
  },
  # ── Florida — Hillsborough ────────────────────────────────────────
  {
    state:                 "FL",
    county:                "Hillsborough",
    auction_type:          "tax_deed",
    status:                "upcoming",
    sale_date:             today + 45,
    end_date:              today + 45,
    registration_opens:    today + 5,
    registration_deadline: today + 37,
    bidding_start:         today + 44,
    latitude:              27.9477,
    longitude:             -82.4584,
    bidding_url:           "https://hillsborough.realforeclose.com",
    source_url:            "https://www.hillsclerk.com/tax-deeds",
    parcel_count:          214,
    total_amount:          5_620_000.00,
    notes:                 "Large auction — expect high competition. Min deposit $5,000."
  },
  # ── Florida — Marion ──────────────────────────────────────────────
  {
    state:                 "FL",
    county:                "Marion",
    auction_type:          "tax_deed",
    status:                "completed",
    sale_date:             today - 30,
    end_date:              today - 30,
    registration_opens:    today - 60,
    registration_deadline: today - 38,
    bidding_start:         today - 31,
    latitude:              29.1872,
    longitude:             -82.1401,
    bidding_url:           nil,
    source_url:            "https://www.marioncountyclerk.org/tax-deeds",
    parcel_count:          58,
    total_amount:          780_000.00,
    notes:                 nil
  },
  # ── Florida — Putnam ──────────────────────────────────────────────
  {
    state:                 "FL",
    county:                "Putnam",
    auction_type:          "tax_deed",
    status:                "upcoming",
    sale_date:             today + 62,
    end_date:              today + 62,
    registration_opens:    today + 10,
    registration_deadline: today + 54,
    bidding_start:         today + 61,
    latitude:              29.6594,
    longitude:             -81.6628,
    bidding_url:           "https://putnam.realtaxdeed.com",
    source_url:            "https://www.putnam-fl.com/coc/tax-deeds",
    parcel_count:          43,
    total_amount:          920_000.00,
    notes:                 "Courthouse auction. Certified funds only."
  },
  # ── Florida — Washington ──────────────────────────────────────────
  {
    state:                 "FL",
    county:                "Washington",
    auction_type:          "tax_deed",
    status:                "upcoming",
    sale_date:             today + 7,
    end_date:              today + 7,
    registration_opens:    today - 7,
    registration_deadline: today + 4,
    bidding_start:         today + 6,
    latitude:              30.6121,
    longitude:             -85.6608,
    bidding_url:           "https://washington.realtaxdeed.com",
    source_url:            "https://www.washingtonclerk.com/tax-deeds",
    parcel_count:          31,
    total_amount:          610_000.00,
    notes:                 nil
  }
]

auctions_data.each do |attrs|
  auction = Auction.find_or_initialize_by(
    state:       attrs[:state],
    county:      attrs[:county],
    sale_date:   attrs[:sale_date]
  )
  auction.assign_attributes(attrs)
  auction.save!(validate: false) # seeds bypass strict validations
  puts "  ✓ #{auction.county}, #{auction.state} [#{auction.status}]"
end

puts "\n=== Seeding Parcels ==="

Parcel.destroy_all if Rails.env.development? && Parcel.count.zero?

# Helper to generate realistic parcels for an auction
def seed_parcels_for(auction, count)
  cities = ["West Palm Beach", "Titusville", "Tampa", "Ocala", "Palatka", "Chipley"]

  count.times do |i|
    opening_bid    = rand(2_000..45_000).to_f
    assessed_value = (opening_bid * rand(1.3..3.5)).round(2)

    # Coordenadas realistas alrededor de la ubicación de la subasta
    lat_jitter = rand(-0.15..0.15)
    lng_jitter = rand(-0.15..0.15)

    parcel_id = "#{auction.state}-#{auction.county.upcase.gsub(/\W/, '')[0..4]}-#{"%06d" % (i + 1001)}"

    Parcel.find_or_create_by!(parcel_id: parcel_id) do |p|
      p.auction_id      = auction.id
      p.address         = "#{rand(100..9999)} #{%w[Oak Main Palm Elm Pine Cedar].sample} #{%w[St Ave Blvd Dr].sample}"
      p.city            = cities.sample
      p.state           = auction.state
      p.zip             = "%05d" % rand(10_000..99_999)
      p.county          = auction.county
      p.opening_bid     = opening_bid
      p.assessed_value  = assessed_value
      p.latitude        = auction.latitude  + lat_jitter
      p.longitude       = auction.longitude + lng_jitter
      p.land_use        = %w[residential commercial vacant].sample
      p.property_type   = %w[Single\ Family Commercial Vacant\ Land Multi-Family].sample
      p.status          = %w[active pending].sample
    end
  end
  puts "  ✓ #{count} parcels seeded for #{auction.county}, #{auction.state}"
end

# Only seed parcels for non-completed auctions (to keep it useful)
Auction.visible.each do |auction|
  count = [auction.parcel_count.to_i, 25].min.clamp(5, 50)
  seed_parcels_for(auction, count)
end

puts "\n=== Done! Seeded #{Auction.count} auctions, #{Parcel.count} parcels ==="
