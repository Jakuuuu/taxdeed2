# frozen_string_literal: true

# ReportPdfBuilder
# Genera PDFs de reportes AVM y Property Scope usando datos de la BD.
# Fuente de datos: tabla parcels + parcel_liens + auction (sincronizados desde Google Sheets).
#
# Uso:
#   pdf = ReportPdfBuilder.build(report_type: "avm", parcel: parcel)
#   pdf.render  # => String con bytes del PDF

class ReportPdfBuilder
  BRAND_COLOR   = "1E3A5F"  # Navy — color primario del design system
  ACCENT_COLOR  = "2E86C1"  # Azul medio
  MUTED_COLOR   = "6C757D"  # Texto secundario
  SUCCESS_COLOR = "28A745"

  def self.build(report_type:, parcel:)
    new(report_type: report_type, parcel: parcel).build
  end

  def initialize(report_type:, parcel:)
    @report_type = report_type
    @parcel      = parcel
    @auction     = parcel.auction
    @liens       = parcel.parcel_liens.to_a
  end

  def build
    Prawn::Document.new(page_size: "LETTER", margin: [40, 50, 40, 50]) do |pdf|
      render_header(pdf)
      pdf.move_down 16

      case @report_type
      when "avm"            then render_avm(pdf)
      when "property_scope" then render_property_scope(pdf)
      end

      render_footer(pdf)
    end
  end

  private

  # ── HEADER ─────────────────────────────────────────────────────────────────

  def render_header(pdf)
    pdf.fill_color BRAND_COLOR
    pdf.fill_rectangle [0, pdf.cursor], pdf.bounds.width, 60
    pdf.fill_color "FFFFFF"
    pdf.bounding_box([10, pdf.cursor - 10], width: pdf.bounds.width - 20, height: 50) do
      pdf.text "TAXDEED LION", size: 18, style: :bold, valign: :center
      pdf.move_down 4
      label = @report_type == "avm" ? "AVM Report — Automated Valuation Model" : "Property Scope Report"
      pdf.text label, size: 10, color: "D0E8F8"
    end
    pdf.fill_color "000000"
    pdf.move_down 8
    pdf.text @parcel.address.to_s, size: 14, style: :bold, color: BRAND_COLOR
    pdf.text "#{[@parcel.county, @parcel.state, @parcel.zip].compact.join(', ')}", size: 10, color: MUTED_COLOR
    pdf.text "APN: #{@parcel.parcel_id || '—'} | Generated: #{Date.today.strftime('%B %d, %Y')}",
             size: 9, color: MUTED_COLOR
    pdf.stroke_color ACCENT_COLOR
    pdf.stroke_horizontal_rule
  end

  # ── AVM REPORT ─────────────────────────────────────────────────────────────

  def render_avm(pdf)
    section_title(pdf, "Valuation Summary")

    opening_bid     = @parcel.opening_bid.to_f
    assessed_value  = @parcel.assessed_value.to_f
    market_value    = @parcel.market_value.to_f
    est_sale        = @parcel.estimated_sale_value.to_f

    # Calculated fields (never stored, computed at render time)
    valor_ajustado  = (opening_bid * 1.16).round(2)
    max_bid_30      = (assessed_value * 0.30).round(2)
    max_bid_35      = (assessed_value * 0.35).round(2)

    data = [
      ["Metric", "Value"],
      ["Opening Bid",                  fmt_currency(opening_bid)],
      ["Opening Bid + 16% Adj.",       fmt_currency(valor_ajustado)],
      ["Assessed Value",               fmt_currency(assessed_value)],
      ["Market Value (Appraisal)",     fmt_currency(market_value)],
      ["Estimated Sale Value",         fmt_currency(est_sale)],
      ["Max Bid at 30% of Assessed",   fmt_currency(max_bid_30)],
      ["Max Bid at 35% of Assessed",   fmt_currency(max_bid_35)],
      ["Price per Acre",               fmt_currency(@parcel.price_per_acre.to_f)]
    ]

    render_table(pdf, data)
    pdf.move_down 16

    section_title(pdf, "Property Details")

    details = [
      ["Field", "Value"],
      ["Land Use",       @parcel.land_use        || "—"],
      ["Zoning",         @parcel.zoning          || "—"],
      ["Lot Area (acres)", fmt_decimal(@parcel.lot_area_acres)],
      ["Lot Area (sqft)",  fmt_decimal(@parcel.sqft_lot)],
      ["Lot Shape",      @parcel.lot_shape        || "—"],
      ["Year Built",     @parcel.year_built&.to_s || "—"],
      ["Homestead Flag", @parcel.homestead_flag   || "—"],
      ["Crime Level",    @parcel.crime_level       || "—"]
    ]

    render_table(pdf, details)
    pdf.move_down 16

    section_title(pdf, "Auction Information")
    if @auction
      auction_data = [
        ["Field", "Value"],
        ["County",         @auction.county             || "—"],
        ["State",          @auction.state              || "—"],
        ["Sale Date",      @auction.sale_date&.strftime("%B %d, %Y") || "—"],
        ["Auction Status", @auction.status&.capitalize || "—"],
        ["Parcel Status",  @parcel.auction_status&.capitalize || "—"]
      ]
      render_table(pdf, auction_data)
    else
      pdf.text "No auction information available.", color: MUTED_COLOR
    end

    pdf.move_down 12
    pdf.text "DISCLAIMER", size: 9, style: :bold, color: MUTED_COLOR
    pdf.text "This AVM report is generated from public data sources for informational purposes only. " \
             "It does not constitute a professional appraisal. Verify all values independently before bidding.",
             size: 8, color: MUTED_COLOR
  end

  # ── PROPERTY SCOPE REPORT ──────────────────────────────────────────────────

  def render_property_scope(pdf)
    section_title(pdf, "Property Information")
    prop_data = [
      ["Field", "Value"],
      ["Address",           @parcel.address                   || "—"],
      ["Property Address",  @parcel.property_address          || "—"],
      ["City/State/Zip",    [@parcel.city, @parcel.state, @parcel.zip].compact.join(", ")],
      ["APN",               @parcel.parcel_id                 || "—"],
      ["Owner Name",        @parcel.owner_name                || "—"],
      ["Legal Description", @parcel.legal_description         || "—"],
      ["Jurisdiction",      @parcel.jurisdiction              || "—"],
      ["Land Use",          @parcel.land_use                  || "—"],
      ["Zoning",            @parcel.zoning                    || "—"],
      ["Homestead Flag",    @parcel.homestead_flag            || "—"]
    ]
    render_table(pdf, prop_data)
    pdf.move_down 16

    section_title(pdf, "Physical Characteristics")
    physical = [
      ["Field", "Value"],
      ["Lot Area (acres)",     fmt_decimal(@parcel.lot_area_acres)],
      ["Lot Area (sqft)",      fmt_decimal(@parcel.sqft_lot)],
      ["Living Area (sqft)",   fmt_decimal(@parcel.sqft_living)],
      ["Minimum Lot Size",     @parcel.minimum_lot_size  || "—"],
      ["Lot Shape",            @parcel.lot_shape         || "—"],
      ["Bedrooms",             @parcel.bedrooms&.to_s    || "—"],
      ["Bathrooms",            @parcel.bathrooms&.to_s   || "—"],
      ["Year Built",           @parcel.year_built&.to_s  || "—"]
    ]
    render_table(pdf, physical)
    pdf.move_down 16

    section_title(pdf, "Utilities & Services")
    utilities = [
      ["Service", "Available"],
      ["Electric",  yn(@parcel.electric)],
      ["Water",     yn(@parcel.water)],
      ["Sewer",     yn(@parcel.sewer)],
      ["HOA/POA",   yn(@parcel.hoa)]
    ]
    render_table(pdf, utilities)
    pdf.move_down 16

    section_title(pdf, "Environmental / FEMA Risk")
    env_data = [
      ["Field", "Value"],
      ["Wetlands",        @parcel.wetlands ? "Yes ⚠️" : "No"],
      ["FEMA Risk Level", @parcel.fema_risk_level || "—"],
      ["FEMA Notes",      @parcel.fema_notes      || "—"],
      ["Crime Level",     @parcel.crime_level     || "—"]
    ]
    render_table(pdf, env_data)
    pdf.move_down 16

    if @liens.any?
      section_title(pdf, "Known Liens & Encumbrances")
      lien_rows = [["Lender", "Type", "Amount", "Status", "Recorded"]]
      @liens.each do |lien|
        lien_rows << [
          lien.lender_name || "—",
          lien.lien_type&.humanize || "—",
          fmt_currency(lien.amount.to_f),
          lien.status&.capitalize || "—",
          lien.recorded_date&.strftime("%m/%d/%Y") || "—"
        ]
      end
      render_table(pdf, lien_rows, col_widths: [130, 80, 75, 70, 80])
      pdf.move_down 12
      pdf.text "NOTE: Tax Deed sales may extinguish most liens except IRS federal tax liens and certain HOA dues. " \
               "Always verify title status independently.",
               size: 8, color: MUTED_COLOR
    else
      pdf.move_down 8
      pdf.text "No lien records found in our database for this parcel.", size: 10, color: MUTED_COLOR
    end

    pdf.move_down 16
    section_title(pdf, "External Resources")
    links = [
      ["Resource", "URL"],
      ["Regrid Map",            @parcel.regrid_url          || "—"],
      ["GIS Image",             @parcel.gis_image_url       || "—"],
      ["Google Maps",           @parcel.google_maps_url     || "—"],
      ["Clerk of Courts",       @parcel.clerk_url           || "—"],
      ["Tax Collector",         @parcel.tax_collector_url   || "—"],
      ["FEMA Flood Map",        @parcel.fema_url            || "—"]
    ]
    render_table(pdf, links)
  end

  # ── FOOTER ─────────────────────────────────────────────────────────────────

  def render_footer(pdf)
    pdf.number_pages "Page <page> of <total> — TaxDeed Lion | cloud.taxsaleresources.com",
                     at: [0, 0],
                     align: :center,
                     size: 8,
                     color: MUTED_COLOR
  end

  # ── HELPERS ────────────────────────────────────────────────────────────────

  def section_title(pdf, text)
    pdf.fill_color ACCENT_COLOR
    pdf.fill_rectangle [0, pdf.cursor], pdf.bounds.width, 18
    pdf.fill_color "FFFFFF"
    pdf.bounding_box([4, pdf.cursor - 3], width: pdf.bounds.width) do
      pdf.text text, size: 10, style: :bold
    end
    pdf.fill_color "000000"
    pdf.move_down 6
  end

  def render_table(pdf, data, col_widths: nil)
    header_bg  = "EBF5FB"
    border_col = "DEE2E6"

    pdf.table(data,
      width:       pdf.bounds.width,
      column_widths: col_widths,
      cell_style:  { size: 9, padding: [5, 8], border_color: border_col, border_width: 0.5 }
    ) do |t|
      # Header row styling
      t.row(0).font_style       = :bold
      t.row(0).background_color = header_bg
      t.row(0).text_color       = BRAND_COLOR
      # Alternating rows
      t.rows(1..-1).each_with_index do |row, i|
        row.background_color = i.even? ? "FFFFFF" : "F8F9FA"
      end
    end
  rescue Prawn::Errors::CannotFit
    # Fallback: render as text if table doesn't fit
    data.each { |row| pdf.text row.join(" | "), size: 8 }
  end

  def fmt_currency(value)
    return "—" if value.nil? || value.zero?
    "$#{format('%,.2f', value)}"
  end

  def fmt_decimal(value)
    return "—" if value.nil? || value.zero?
    format('%,.2f', value)
  end

  def yn(value)
    case value&.downcase
    when "yes" then "✓ Yes"
    when "no"  then "✗ No"
    else "—"
    end
  end
end
