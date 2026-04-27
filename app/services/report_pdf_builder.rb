# frozen_string_literal: true

# ReportPdfBuilder
# Genera el Property Intelligence Report en PDF usando datos de la BD.
# Fuente de datos: tabla parcels + parcel_liens + auction (sincronizados desde Google Sheets).
#
# Uso:
#   pdf = ReportPdfBuilder.build(parcel: parcel)
#   pdf.render  # => String con bytes del PDF

class ReportPdfBuilder
  BRAND_COLOR   = "1E3A5F"  # Navy — color primario del design system
  ACCENT_COLOR  = "2E86C1"  # Azul medio
  MUTED_COLOR   = "6C757D"  # Texto secundario
  SUCCESS_COLOR = "28A745"

  def self.build(parcel:, **_opts)
    new(parcel: parcel).build
  end

  def initialize(parcel:, **_opts)
    @parcel  = parcel
    @auction = parcel.auction
    @liens   = parcel.parcel_liens.to_a
  end

  def build
    Prawn::Document.new(page_size: "LETTER", margin: [40, 50, 40, 50]) do |pdf|
      render_header(pdf)
      pdf.move_down 16
      render_ficha_snapshot(pdf)
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
      pdf.text "Property Intelligence Report", size: 10, color: "D0E8F8"
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

  # ── PROPERTY INTELLIGENCE REPORT (PDF completo) ─────────────────────────
  # Combina todas las secciones de la ficha en un solo documento.
  # Orden: Investment → Property Info → Physical → Valuation → Utilities →
  #        Environmental → Auction → Liens → External Resources → Disclaimer.

  def render_ficha_snapshot(pdf)
    # ── 1. Investment Summary ──────────────────────────────────────────
    section_title(pdf, "Investment Summary")

    opening_bid    = @parcel.opening_bid.to_f
    assessed_value = @parcel.assessed_value.to_f
    est_sale       = @parcel.estimated_sale_value.to_f
    price_estimate = @parcel.price_estimate.to_f
    max_bid_30     = @parcel.max_bid_30.to_f
    max_bid_35     = @parcel.max_bid_35.to_f

    invest_data = [
      ["Metric", "Value"],
      ["Opening Bid",           fmt_currency(opening_bid)],
      ["Assessed Value",        fmt_currency(assessed_value)],
      ["Estimated Sale Value",  fmt_currency(est_sale)],
      ["Price Estimate",        fmt_currency(price_estimate)],
      ["Max Bid at 30%",        fmt_currency(max_bid_30)],
      ["Max Bid at 35%",        fmt_currency(max_bid_35)],
      ["Price per Acre",        fmt_currency(@parcel.price_per_acre.to_f)]
    ]
    render_table(pdf, invest_data)
    pdf.move_down 16

    # ── 2. Property Information ───────────────────────────────────────
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

    # ── 3. Physical Characteristics ───────────────────────────────────
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

    # ── 4. Valuation & Tax ────────────────────────────────────────────
    section_title(pdf, "Valuation & Tax")
    val_data = [
      ["Metric", "Value"],
      ["Assessed Value",        fmt_currency(assessed_value)],
      ["Estimated Sale Value",  fmt_currency(est_sale)],
      ["Delinquent Amount",     fmt_currency(@parcel.delinquent_amount.to_f)],
      ["Crime Level",           @parcel.crime_level || "—"]
    ]
    render_table(pdf, val_data)
    pdf.move_down 16

    # ── 5. Utilities & Services ───────────────────────────────────────
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

    # ── 6. Environmental / FEMA Risk ──────────────────────────────────
    section_title(pdf, "Environmental / FEMA Risk")
    env_data = [
      ["Field", "Value"],
      ["Wetlands",        @parcel.wetlands ? "Yes ⚠️" : "No"],
      ["FEMA Risk Level", @parcel.fema_risk_level || "—"],
      ["FEMA Notes",      @parcel.fema_notes      || "—"]
    ]
    render_table(pdf, env_data)
    pdf.move_down 16

    # ── 7. Auction Information ────────────────────────────────────────
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
    pdf.move_down 16

    # ── 8. Known Liens & Encumbrances ─────────────────────────────────
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
      pdf.move_down 8
      pdf.text "NOTE: Tax Deed sales may extinguish most liens except IRS federal tax liens and certain HOA dues. " \
               "Always verify title status independently.",
               size: 8, color: MUTED_COLOR
      pdf.move_down 16
    end

    # ── 9. External Resources ─────────────────────────────────────────
    section_title(pdf, "External Resources")
    links = [
      ["Resource", "URL"],
      ["Regrid Map",                @parcel.regrid_url             || "—"],
      ["GIS Image",                 @parcel.gis_image_url          || "—"],
      ["Google Maps",               @parcel.google_maps_url        || "—"],
      ["Property Appraisal Page",   @parcel.property_appraiser_url || "—"],
      ["Clerk of Courts",           @parcel.clerk_url              || "—"],
      ["Tax Collector",             @parcel.tax_collector_url      || "—"],
      ["FEMA Flood Map",            @parcel.fema_url               || "—"]
    ]
    render_table(pdf, links)

    # ── 10. Legal Disclaimer ──────────────────────────────────────────
    pdf.move_down 16
    pdf.text "LEGAL DISCLAIMER", size: 9, style: :bold, color: MUTED_COLOR
    pdf.text "This Property Intelligence Report is generated from public data sources for informational purposes only. " \
             "It does not constitute a professional appraisal, legal advice, or investment recommendation. " \
             "TaxDeed Lion does not guarantee the accuracy or completeness of the information presented. " \
             "Verify all values independently and consult licensed professionals before making investment decisions.",
             size: 8, color: MUTED_COLOR
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
