# frozen_string_literal: true

# ==============================================================================
# Test: SyncSheetJob + SheetRowProcessor — Auditoría de Integridad de Datos
#
# Este archivo de test valida que el pipeline completo de sincronización
# Google Sheets → PostgreSQL sea un espejo perfecto y parseado de los datos
# premium, incluso cuando el payload del Sheet viene "sucio" (con espacios,
# símbolos de dólar, campos vacíos, NBSP, formatos inconsistentes, etc.).
#
# Cubre las 4 áreas de la auditoría:
#   1. Parseo de tipos de datos (moneda, decimales, fechas, booleanos)
#   2. Mapeo exhaustivo de datos premium (todos los campos del Blur Paywall)
#   3. Blindaje de inmunidad del Mini CRM (parcel_user_tags/notes intactos)
#   4. Espejo Infalible (celdas borradas → NULL en PostgreSQL)
#
# Ejecutar con:
#   bundle exec rails test test/jobs/sync_sheet_job_test.rb
#
# ==============================================================================

require "test_helper"

class SheetRowProcessorTest < ActiveSupport::TestCase
  include SheetColumnMap

  # ============================================================================
  # SETUP: Construir filas simuladas del Google Sheet "sucias"
  # ============================================================================

  # Genera una fila del Sheet con datos sucios pero válidos.
  # Simula exactamente lo que Google Sheets API v4 retorna como un Array de strings.
  def dirty_sheet_row
    row = Array.new(80, nil)

    # ── Identificación ──────────────────────────────────────────────────────
    row[STATE]          = "  FL "                          # Espacios alrededor
    row[COUNTY]         = " Escambia  "                    # Trailing spaces
    row[PARCEL_ID]      = " 01-2S-30-0000-001-002 "        # Espacios
    row[AUCTION_DATE]   = " 05/15/2026 "                   # Fecha con espacios

    # ── Financiero (FORMATO SUCIO — prueba crítica de parse_currency) ──────
    row[MARKET_VALUE]   = "$125,000"                       # Símbolo de dólar + coma
    row[OPENING_BID]    = " $25,000.50 "                   # Dólar + coma + decimal + espacios
    row[ASSESSED_VALUE] = "95000"                          # Sin formato — solo número
    row[ESTIMATED_SALE_VALUE] = "$85,000"                  # Dólar + coma

    # ── Físico (FORMATO SUCIO — prueba de parse_decimal) ──────────────────
    row[LOT_AREA_ACRES] = " 2.5000 "                       # Decimal con espacios
    row[SQFT_LOT]       = "10,890"                         # Coma de miles
    row[SQFT_LIVING]    = " 1,500.75 "                     # Coma + decimal + espacios

    # ── Texto plano ────────────────────────────────────────────────────────
    row[MINIMUM_LOT_SIZE]   = " No minimum lot area unless prescribed by use. "
    row[ZONING]             = " R-1 "                      # Código con espacios
    row[JURISDICTION]       = "ESCAMBIA COUNTY UNINCORPORATED "
    row[LAND_USE]           = " Single Family "
    row[HAB]                = " 3 "                         # col O "Habitaciones" → bedrooms (entero)
    row[BD]                 = " 2.5 "                       # col P "BD" → bathrooms (decimal)
    row[OWNER_NAME]         = " John Doe "
    row[OWNER_MAIL_ADDRESS] = " 123 Main St, Pensacola FL 32501 "
    row[PROPERTY_ADDRESS]   = " 456 Oak Ave "
    row[ZIP]                = " 32501 "
    row[CITY]               = " Pensacola "
    row[LEGAL_DESCRIPTION]  = " LOT 2 BLK A EASTVIEW ESTATES "

    # ── Clasificación ──────────────────────────────────────────────────────
    row[CRIME_LEVEL]    = " Low "
    row[HOMESTEAD_FLAG] = " Investor "

    # ── Utilities ──────────────────────────────────────────────────────────
    row[ELECTRIC] = " yes "                                # Lowercase + espacios
    row[WATER]    = "Yes"                                  # Capitalizado
    row[SEWER]    = " YES "                                # Uppercase + espacios
    row[LOT_SHAPE] = " Flat "
    row[HOA]      = " no "

    # ── FEMA / Medioambiente ───────────────────────────────────────────────
    row[WETLANDS_RAW]   = " yes "                          # Boolean con espacios
    row[FEMA_RISK_LEVEL] = " Zone X (Minimal risk) "
    row[FEMA_NOTES]     = " Outside 500-year floodplain "
    row[FEMA_URL]       = " https://msc.fema.gov/portal/search?AddressQuery=32501 "

    # ── Coordenadas (formato dirty) ────────────────────────────────────────
    row[COORDINATES_RAW] = " 30.452145, -87.270564 "       # Espacios alrededor

    # ── Links externos ─────────────────────────────────────────────────────
    row[REGRID_URL]         = " https://app.regrid.com/us/fl/escambia/01-2S "
    row[GIS_IMAGE_URL]      = " https://gis.escambiaclerk.com/map/01-2S-30.png "
    row[GOOGLE_MAPS_URL]    = " https://maps.google.com/?q=30.452145,-87.270564 "
    row[PROPERTY_IMAGE_URL] = " https://storage.googleapis.com/images/01-2S.jpg "
    row[CLERK_URL]          = " https://escambiaclerk.com/search "
    row[TAX_COLLECTOR_URL]  = " https://escambiatax.com/search "

    row
  end

  # Fila con campos vacíos (simula celda borrada en el Sheet)
  def blank_financial_row
    row = Array.new(80, nil)
    row[STATE]     = "FL"
    row[COUNTY]    = "Orange"
    row[PARCEL_ID] = "99-0001-XYZ"
    row[AUCTION_DATE] = "06/01/2026"
    # Todos los campos financieros y premium VACÍOS → deben ser nil en BD
    row
  end

  # Fila completamente vacía → debe ser :skipped
  def empty_row
    Array.new(80, nil)
  end

  # Fila con moneda en formatos edge-case extremos
  def extreme_currency_row
    row = Array.new(80, nil)
    row[STATE]       = "FL"
    row[COUNTY]      = "Escambia"
    row[PARCEL_ID]   = "EXTREME-CURRENCY-001"
    row[AUCTION_DATE] = "07/20/2026"
    row[OPENING_BID]  = "$1,234,567.89"              # Millones con comas
    row[ASSESSED_VALUE] = "0"                        # Cero explícito
    row[MARKET_VALUE]   = "  $0.00  "                # Cero con dólar y espacios
    row[ESTIMATED_SALE_VALUE] = "N/A"                # Texto no numérico
    row[LOT_AREA_ACRES] = "0.25"                     # Fracción de acre
    row
  end

  # ============================================================================
  # TEST 1: PARSEO DE MONEDA (parse_currency)
  # ============================================================================

  test "parse_currency handles dollar sign with commas" do
    processor = SheetRowProcessor.new([])
    assert_equal BigDecimal("25000"), processor.send(:parse_currency, "$25,000")
  end

  test "parse_currency handles plain number" do
    processor = SheetRowProcessor.new([])
    assert_equal BigDecimal("25000"), processor.send(:parse_currency, "25000")
  end

  test "parse_currency handles dollar sign with commas and decimals" do
    processor = SheetRowProcessor.new([])
    assert_equal BigDecimal("25000.50"), processor.send(:parse_currency, "$25,000.50")
  end

  test "parse_currency handles spaces around value" do
    processor = SheetRowProcessor.new([])
    assert_equal BigDecimal("25000"), processor.send(:parse_currency, " $25,000 ")
  end

  test "parse_currency returns nil for blank" do
    processor = SheetRowProcessor.new([])
    assert_nil processor.send(:parse_currency, "")
    assert_nil processor.send(:parse_currency, nil)
    assert_nil processor.send(:parse_currency, "   ")
  end

  test "parse_currency returns nil for non-numeric text" do
    processor = SheetRowProcessor.new([])
    assert_nil processor.send(:parse_currency, "N/A")
    assert_nil processor.send(:parse_currency, "TBD")
    assert_nil processor.send(:parse_currency, "pending")
  end

  test "parse_currency handles zero correctly" do
    processor = SheetRowProcessor.new([])
    assert_equal BigDecimal("0"), processor.send(:parse_currency, "$0")
    assert_equal BigDecimal("0"), processor.send(:parse_currency, "0")
    assert_equal BigDecimal("0"), processor.send(:parse_currency, "$0.00")
  end

  test "parse_currency handles millions with commas" do
    processor = SheetRowProcessor.new([])
    assert_equal BigDecimal("1234567.89"), processor.send(:parse_currency, "$1,234,567.89")
  end

  # ============================================================================
  # TEST 2: PARSEO DE DECIMALES (parse_decimal)
  # ============================================================================

  test "parse_decimal handles comma-separated thousands" do
    processor = SheetRowProcessor.new([])
    assert_equal BigDecimal("10890"), processor.send(:parse_decimal, "10,890")
  end

  test "parse_decimal handles decimal with spaces" do
    processor = SheetRowProcessor.new([])
    assert_equal BigDecimal("1500.75"), processor.send(:parse_decimal, " 1,500.75 ")
  end

  test "parse_decimal handles simple decimal" do
    processor = SheetRowProcessor.new([])
    assert_equal BigDecimal("2.5"), processor.send(:parse_decimal, "2.5000")
  end

  test "parse_decimal returns nil for blank" do
    processor = SheetRowProcessor.new([])
    assert_nil processor.send(:parse_decimal, "")
    assert_nil processor.send(:parse_decimal, nil)
  end

  test "parse_decimal returns nil for non-numeric" do
    processor = SheetRowProcessor.new([])
    assert_nil processor.send(:parse_decimal, "N/A")
  end

  # ============================================================================
  # TEST 3: PARSEO DE FECHAS (parse_date)
  # ============================================================================

  test "parse_date handles MM/DD/YYYY format" do
    processor = SheetRowProcessor.new([])
    assert_equal Date.new(2026, 5, 15), processor.send(:parse_date, "05/15/2026")
  end

  test "parse_date handles date with spaces" do
    processor = SheetRowProcessor.new([])
    assert_equal Date.new(2026, 5, 15), processor.send(:parse_date, " 05/15/2026 ".strip)
  end

  test "parse_date returns nil for blank" do
    processor = SheetRowProcessor.new([])
    assert_nil processor.send(:parse_date, "")
    assert_nil processor.send(:parse_date, nil)
  end

  test "parse_date returns nil for garbage" do
    processor = SheetRowProcessor.new([])
    assert_nil processor.send(:parse_date, "not-a-date")
  end

  test "parse_date handles alternative format via fallback" do
    processor = SheetRowProcessor.new([])
    result = processor.send(:parse_date, "2026-05-15")
    assert_equal Date.new(2026, 5, 15), result
  end

  # ============================================================================
  # TEST 4: PARSEO DE BOOLEANOS (parse_boolean)
  # ============================================================================

  test "parse_boolean handles yes variations" do
    processor = SheetRowProcessor.new([])
    assert_equal true, processor.send(:parse_boolean, "yes")
    assert_equal true, processor.send(:parse_boolean, "Yes")
    assert_equal true, processor.send(:parse_boolean, " YES ")
    assert_equal true, processor.send(:parse_boolean, " yes ")
  end

  test "parse_boolean handles no" do
    processor = SheetRowProcessor.new([])
    assert_equal false, processor.send(:parse_boolean, "no")
    assert_equal false, processor.send(:parse_boolean, "No")
    assert_equal false, processor.send(:parse_boolean, " NO ")
  end

  test "parse_boolean returns nil for blank" do
    processor = SheetRowProcessor.new([])
    assert_nil processor.send(:parse_boolean, "")
    assert_nil processor.send(:parse_boolean, nil)
  end

  # ============================================================================
  # TEST 5: PARSEO DE COORDENADAS (parsed_coords)
  # ============================================================================

  test "parsed_coords handles standard format with spaces" do
    processor = SheetRowProcessor.new(dirty_sheet_row)
    coords = processor.send(:parsed_coords)
    assert_equal BigDecimal("30.452145"), coords[:latitude]
    assert_equal BigDecimal("-87.270564"), coords[:longitude]
  end

  test "parsed_coords returns nils for blank cell" do
    row = Array.new(80, nil)
    row[COORDINATES_RAW] = ""
    processor = SheetRowProcessor.new(row)
    coords = processor.send(:parsed_coords)
    assert_nil coords[:latitude]
    assert_nil coords[:longitude]
  end

  test "parsed_coords returns nils for garbage" do
    row = Array.new(80, nil)
    row[COORDINATES_RAW] = "garbage data"
    processor = SheetRowProcessor.new(row)
    coords = processor.send(:parsed_coords)
    assert_nil coords[:latitude]
    assert_nil coords[:longitude]
  end

  test "parsed_coords ALWAYS returns both keys even when nil" do
    row = Array.new(80, nil)
    processor = SheetRowProcessor.new(row)
    coords = processor.send(:parsed_coords)
    assert coords.key?(:latitude), "parsed_coords MUST always return :latitude key"
    assert coords.key?(:longitude), "parsed_coords MUST always return :longitude key"
  end

  # ============================================================================
  # TEST 6: MAPEO EXHAUSTIVO DE DATOS PREMIUM — Fila Sucia Completa
  # Valida que TODOS los campos premium del Blur Paywall se extraigan
  # correctamente de una fila "sucia" del Sheet y se persistan en PostgreSQL.
  # ============================================================================

  test "complete dirty row produces correct parcel with all premium fields" do
    result = SheetRowProcessor.process(dirty_sheet_row)

    assert_equal :added, result

    parcel = Parcel.find_by!(
      state: "FL", county: "Escambia", parcel_id: "01-2S-30-0000-001-002"
    )

    # ── Identificación (sin espacios) ────────────────────────────────────
    assert_equal "FL",                        parcel.state
    assert_equal "Escambia",                  parcel.county
    assert_equal "01-2S-30-0000-001-002",     parcel.parcel_id
    assert_equal "456 Oak Ave",               parcel.address
    assert_equal "456 Oak Ave",               parcel.property_address
    assert_equal "32501",                     parcel.zip
    assert_equal "Pensacola",                 parcel.city
    assert_equal "John Doe",                  parcel.owner_name

    # ── Financiero (sanitizado desde formato sucio) ──────────────────────
    assert_equal BigDecimal("125000"),         parcel.market_value
    assert_equal BigDecimal("25000.50"),        parcel.opening_bid
    assert_equal BigDecimal("95000"),           parcel.assessed_value
    assert_equal BigDecimal("85000"),           parcel.estimated_sale_value

    # ── Price Per Acre (calculado: 25000.50 / 2.5 = 10000.20) ────────────
    assert_equal BigDecimal("10000.20"),        parcel.price_per_acre

    # ── Físico (sanitizado) ──────────────────────────────────────────────
    assert_equal BigDecimal("2.5"),             parcel.lot_area_acres
    assert_equal BigDecimal("10890"),            parcel.sqft_lot
    assert_equal BigDecimal("1500.75"),          parcel.sqft_living

    # ── Premium: Zonificación ────────────────────────────────────────────
    assert_equal "R-1",                         parcel.zoning

    # ── Premium: Locación ────────────────────────────────────────────────
    assert_equal "ESCAMBIA COUNTY UNINCORPORATED", parcel.jurisdiction
    assert_equal "Single Family",               parcel.land_use

    # ── Premium: Habitaciones/Baños — guardia anti-SWAP (col O→bedrooms, col P→bathrooms) ──
    assert_equal 3,                              parcel.bedrooms
    assert_equal BigDecimal("2.5"),              parcel.bathrooms

    # ── Premium: Clasificación Inversión ─────────────────────────────────
    assert_equal "Investor",                    parcel.homestead_flag
    assert_equal "Low",                         parcel.crime_level

    # ── Premium: Utilities / Accesos ─────────────────────────────────────
    assert_equal "yes",                         parcel.electric
    assert_equal "Yes",                         parcel.water
    assert_equal "YES",                         parcel.sewer
    assert_equal "Flat",                        parcel.lot_shape
    assert_equal "no",                          parcel.hoa

    # ── Premium: FEMA / Riesgo Inundación ────────────────────────────────
    assert_equal true,                          parcel.wetlands
    assert_equal "Zone X (Minimal risk)",       parcel.fema_risk_level
    assert_equal "Outside 500-year floodplain", parcel.fema_notes
    assert parcel.fema_url.present?,            "FEMA URL must be present"

    # ── Coordenadas ──────────────────────────────────────────────────────
    assert_equal BigDecimal("30.452145"),        parcel.latitude
    assert_equal BigDecimal("-87.270564"),       parcel.longitude

    # ── Links externos ───────────────────────────────────────────────────
    assert parcel.regrid_url.present?,          "Regrid URL must be present"
    assert parcel.gis_image_url.present?,       "GIS Image URL must be present"
    assert parcel.google_maps_url.present?,     "Google Maps URL must be present"
    assert parcel.property_image_url.present?,  "Property Image URL must be present"
    assert parcel.clerk_url.present?,           "Clerk URL must be present"
    assert parcel.tax_collector_url.present?,   "Tax Collector URL must be present"

    # ── Metadata ─────────────────────────────────────────────────────────
    assert_equal "google_sheets",               parcel.data_source
    assert parcel.last_synced_at.present?,      "last_synced_at must be set"

    # ── Legal Description ────────────────────────────────────────────────
    assert_equal "LOT 2 BLK A EASTVIEW ESTATES", parcel.legal_description
  end

  # ============================================================================
  # TEST 7: ESPEJO INFALIBLE — Celdas Borradas → NULL en PostgreSQL
  # ============================================================================

  test "blank cells in Sheet result in nil fields in PostgreSQL" do
    result = SheetRowProcessor.process(blank_financial_row)
    assert_equal :added, result

    parcel = Parcel.find_by!(
      state: "FL", county: "Orange", parcel_id: "99-0001-XYZ"
    )

    # Todos los campos premium deben ser nil
    assert_nil parcel.opening_bid,         "opening_bid must be nil for blank cell"
    assert_nil parcel.assessed_value,      "assessed_value must be nil for blank cell"
    assert_nil parcel.market_value,        "market_value must be nil for blank cell"
    assert_nil parcel.estimated_sale_value, "estimated_sale_value must be nil for blank cell"
    assert_nil parcel.lot_area_acres,      "lot_area_acres must be nil for blank cell"
    assert_nil parcel.sqft_lot,            "sqft_lot must be nil for blank cell"
    assert_nil parcel.sqft_living,         "sqft_living must be nil for blank cell"
    assert_nil parcel.zoning,              "zoning must be nil for blank cell"
    assert_nil parcel.jurisdiction,        "jurisdiction must be nil for blank cell"
    assert_nil parcel.land_use,            "land_use must be nil for blank cell"
    assert_nil parcel.homestead_flag,      "homestead_flag must be nil for blank cell"
    assert_nil parcel.crime_level,         "crime_level must be nil for blank cell"
    assert_nil parcel.electric,            "electric must be nil for blank cell"
    assert_nil parcel.water,              "water must be nil for blank cell"
    assert_nil parcel.sewer,              "sewer must be nil for blank cell"
    assert_nil parcel.hoa,                "hoa must be nil for blank cell"
    assert_nil parcel.wetlands,            "wetlands must be nil for blank cell"
    assert_nil parcel.fema_risk_level,     "fema_risk_level must be nil for blank cell"
    assert_nil parcel.latitude,            "latitude must be nil for blank cell"
    assert_nil parcel.longitude,           "longitude must be nil for blank cell"
    assert_nil parcel.price_per_acre,      "price_per_acre must be nil when deps are nil"
  end

  # ============================================================================
  # TEST 8: ESPEJO — Datos existentes se limpian cuando Sheet se borra
  # ============================================================================

  test "existing parcel data gets cleared when Sheet cell is emptied" do
    # Paso 1: Crear parcela con datos completos
    SheetRowProcessor.process(dirty_sheet_row)
    parcel = Parcel.find_by!(state: "FL", county: "Escambia", parcel_id: "01-2S-30-0000-001-002")

    # Validar que tiene datos
    assert_equal BigDecimal("25000.50"), parcel.opening_bid
    assert_equal BigDecimal("30.452145"), parcel.latitude
    assert_equal "R-1", parcel.zoning

    # Paso 2: Procesar la misma parcela pero con campos vacíos
    cleared_row = Array.new(80, nil)
    cleared_row[STATE]     = "FL"
    cleared_row[COUNTY]    = "Escambia"
    cleared_row[PARCEL_ID] = "01-2S-30-0000-001-002"
    cleared_row[AUCTION_DATE] = "05/15/2026"
    # Todos los demás campos están vacíos → deben limpiarse en BD

    result = SheetRowProcessor.process(cleared_row)
    assert_equal :updated, result

    parcel.reload

    # Los campos deben haberse limpiado (espejo infalible)
    assert_nil parcel.opening_bid,     "opening_bid debe limpiarse cuando la celda se borra"
    assert_nil parcel.latitude,        "latitude debe limpiarse cuando coord se borra"
    assert_nil parcel.longitude,       "longitude debe limpiarse cuando coord se borra"
    assert_nil parcel.zoning,          "zoning debe limpiarse cuando la celda se borra"
    assert_nil parcel.assessed_value,  "assessed_value debe limpiarse"
    assert_nil parcel.market_value,    "market_value debe limpiarse"
    assert_nil parcel.wetlands,        "wetlands debe limpiarse"
    assert_nil parcel.fema_risk_level, "fema_risk_level debe limpiarse"
    assert_nil parcel.electric,        "electric debe limpiarse"
    assert_nil parcel.hoa,             "hoa debe limpiarse"
  end

  # ============================================================================
  # TEST 9: FILA VACÍA → :skipped
  # ============================================================================

  test "empty row is skipped" do
    result = SheetRowProcessor.process(empty_row)
    assert_equal :skipped, result
  end

  test "row with only whitespace in parcel_id and address is skipped" do
    row = Array.new(80, nil)
    row[PARCEL_ID] = "   "
    row[ADDRESS] = "   "
    result = SheetRowProcessor.process(row)
    assert_equal :skipped, result
  end

  # ============================================================================
  # TEST 10: UPSERT — Segunda pasada actualiza, no duplica
  # ============================================================================

  test "processing same row twice updates instead of duplicating" do
    SheetRowProcessor.process(dirty_sheet_row)
    initial_count = Parcel.count

    SheetRowProcessor.process(dirty_sheet_row)
    assert_equal initial_count, Parcel.count, "No debe crear duplicados"
  end

  test "second processing returns :updated" do
    SheetRowProcessor.process(dirty_sheet_row)
    result = SheetRowProcessor.process(dirty_sheet_row)
    assert_equal :updated, result
  end

  # ============================================================================
  # TEST 11: CRM IMMUNITY — El sync NUNCA toca datos del Mini CRM
  # ============================================================================

  test "CRM immunity guard blocks protected columns" do
    processor = SheetRowProcessor.new(dirty_sheet_row)

    # Simular un hash que contenga campos CRM protegidos
    evil_attrs = {
      state: "FL",
      parcel_user_tags: "some value"
    }

    assert_raises(ActiveRecord::RecordNotSaved) do
      processor.send(:enforce_crm_immunity!, evil_attrs)
    end
  end

  test "CRM immunity guard allows clean attributes" do
    processor = SheetRowProcessor.new(dirty_sheet_row)

    clean_attrs = {
      state: "FL",
      county: "Escambia",
      opening_bid: BigDecimal("25000"),
      zoning: "R-1"
    }

    # No debe lanzar ningún error
    assert_nothing_raised do
      processor.send(:enforce_crm_immunity!, clean_attrs)
    end
  end

  test "CRM immunity blocks all four protected column variants" do
    processor = SheetRowProcessor.new(dirty_sheet_row)

    %w[parcel_user_tags parcel_user_notes user_tags user_notes].each do |column|
      attrs = { column.to_sym => "injected" }
      assert_raises(ActiveRecord::RecordNotSaved, "Should block #{column}") do
        processor.send(:enforce_crm_immunity!, attrs)
      end
    end
  end

  test "sync does NOT touch Mini CRM tables (parcel_user_tags integrity)" do
    # Paso 1: Crear parcela y asociar datos CRM
    SheetRowProcessor.process(dirty_sheet_row)
    parcel = Parcel.find_by!(state: "FL", county: "Escambia", parcel_id: "01-2S-30-0000-001-002")
    user = User.create!(email: "crm-test@example.com", password: "password123456")

    # Crear tag y nota CRM del usuario
    tag = ParcelUserTag.upsert_for!(user: user, parcel: parcel, tag: "target")
    note = ParcelUserNote.create!(user: user, parcel: parcel, body: "Great investment opportunity")

    # Paso 2: Re-sync la parcela (simula 2da ejecución del job)
    SheetRowProcessor.process(dirty_sheet_row)

    # Paso 3: Verificar que CRM data sobrevivió intacta
    assert_equal 1, ParcelUserTag.where(user: user, parcel: parcel).count,
                 "El tag CRM debe sobrevivir al re-sync"
    assert_equal "target", ParcelUserTag.find_by(user: user, parcel: parcel).tag,
                 "El valor del tag CRM no debe cambiar"
    assert_equal 1, ParcelUserNote.where(user: user, parcel: parcel).count,
                 "La nota CRM debe sobrevivir al re-sync"
    assert_equal "Great investment opportunity",
                 ParcelUserNote.find_by(user: user, parcel: parcel).body,
                 "El contenido de la nota CRM no debe cambiar"
  end

  # ============================================================================
  # TEST 12: EXTREME CURRENCY FORMATS
  # ============================================================================

  test "extreme currency formats are handled correctly" do
    result = SheetRowProcessor.process(extreme_currency_row)
    assert_equal :added, result

    parcel = Parcel.find_by!(
      state: "FL", county: "Escambia", parcel_id: "EXTREME-CURRENCY-001"
    )

    assert_equal BigDecimal("1234567.89"), parcel.opening_bid,
                 "Millions con comas deben parsearse correctamente"
    assert_equal BigDecimal("0"), parcel.assessed_value,
                 "Cero explícito debe persistir como 0, no nil"
    assert_equal BigDecimal("0"), parcel.market_value,
                 "$0.00 debe persistir como 0, no nil"
    assert_nil parcel.estimated_sale_value,
               "N/A debe convertirse a nil"
  end

  # ============================================================================
  # TEST 13: AUCTION SE CREA O REUTILIZA CORRECTAMENTE
  # ============================================================================

  test "auction is created from sheet row data" do
    SheetRowProcessor.process(dirty_sheet_row)

    auction = Auction.find_by(state: "FL", county: "Escambia")
    assert_not_nil auction, "Auction debe crearse automáticamente"
    assert_equal "tax_deed", auction.auction_type
    assert_equal "upcoming", auction.status
    assert_equal Date.new(2026, 5, 15), auction.sale_date
  end

  test "same auction is reused for same county+state+date" do
    SheetRowProcessor.process(dirty_sheet_row)
    initial_auction_count = Auction.count

    # Procesar otra parcela del mismo condado/estado/fecha
    row2 = dirty_sheet_row.dup
    row2[PARCEL_ID] = "DIFFERENT-APN-002"
    SheetRowProcessor.process(row2)

    assert_equal initial_auction_count, Auction.count,
                 "No debe crear auction duplicada para el mismo condado/estado/fecha"
  end

  # ============================================================================
  # TEST 14: col() HELPER — Sanitización de celdas
  # ============================================================================

  test "col returns nil for empty string" do
    processor = SheetRowProcessor.new([""])
    assert_nil processor.send(:col, 0)
  end

  test "col returns nil for whitespace-only string" do
    processor = SheetRowProcessor.new(["   "])
    assert_nil processor.send(:col, 0)
  end

  test "col strips leading and trailing whitespace" do
    processor = SheetRowProcessor.new(["  hello  "])
    assert_equal "hello", processor.send(:col, 0)
  end

  test "col returns nil for out-of-bounds index" do
    processor = SheetRowProcessor.new(["a", "b"])
    assert_nil processor.send(:col, 99)
  end

  # ============================================================================
  # TEST 15: REGRESSION — Los atributos del upsert NO contienen campos CRM
  # Verifica estáticamente que el hash de attrs en upsert_parcel no incluya
  # ninguna key que haga referencia a tablas/columnas CRM protegidas.
  # ============================================================================

  test "upsert attrs hash does not contain any CRM column keys" do
    # Inspección estática del código fuente
    source = File.read(Rails.root.join("app/services/sheet_row_processor.rb"))

    SheetRowProcessor::CRM_IMMUNE_COLUMNS.each do |col_name|
      # Verificar que la key no aparece como símbolo en el hash de attrs
      assert_not source.include?("#{col_name}:"),
                 "El código fuente NO debe contener '#{col_name}:' como key en el hash de attrs"
    end
  end
end

# ==============================================================================
# Test: SyncSheetJob (integración)
# ==============================================================================

class SyncSheetJobIntegrationTest < ActiveSupport::TestCase
  include SheetColumnMap

  test "SyncSheetJob validates expected headers correctly" do
    job = SyncSheetJob.new

    # Headers correctos
    correct_headers = Array.new(10, "")
    correct_headers[0] = "State"
    correct_headers[1] = "County"
    correct_headers[2] = "Parcel Number"
    correct_headers[6] = "Auction Date"
    correct_headers[8] = "Min. Bid"

    # No debe lanzar error ni warning (verificamos que no explota)
    assert_nothing_raised do
      job.send(:validate_headers, correct_headers)
    end
  end

  test "SyncSheetJob handles headers with NBSP and trailing spaces" do
    job = SyncSheetJob.new

    # Headers con espacios sucios
    dirty_headers = Array.new(10, "")
    dirty_headers[0] = "  State  "
    dirty_headers[1] = "County\u00A0"      # NBSP trailing
    dirty_headers[2] = " Parcel Number "
    dirty_headers[6] = "Auction Date   "
    dirty_headers[8] = " Min. Bid"

    # El strip en validate_headers debe limpiar esto
    assert_nothing_raised do
      job.send(:validate_headers, dirty_headers)
    end
  end
end
