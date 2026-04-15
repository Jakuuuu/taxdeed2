# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════════════
# AUDITORÍA DE INTEGRIDAD DE DATOS — SyncSheetJob + SheetRowProcessor
# ═══════════════════════════════════════════════════════════════════════════════
#
# Ejecutar con:  rails runner test/scripts/data_integrity_audit.rb
#
# Valida las 4 áreas de la auditoría:
#   1. Parseo de tipos de datos (moneda, decimales, fechas, booleanos)
#   2. Mapeo exhaustivo de datos premium (todos los campos del Blur Paywall)
#   3. Blindaje de inmunidad del Mini CRM (parcel_user_tags/notes intactos)
#   4. Espejo Infalible (celdas borradas → NULL en PostgreSQL)
#
# Todas las pruebas usan SAVEPOINT + ROLLBACK para no dejar basura en la BD.
#
# ═══════════════════════════════════════════════════════════════════════════════

module DataIntegrityAudit
  SEPARATOR = "═" * 78
  PASS = "✅ PASS"
  FAIL = "❌ FAIL"

  class << self
    attr_accessor :total_assertions, :passed_assertions, :failed_assertions, :failures

    def run_all
      self.total_assertions  = 0
      self.passed_assertions = 0
      self.failed_assertions = 0
      self.failures          = []

      puts "\n#{SEPARATOR}"
      puts "  🔬 AUDITORÍA DE INTEGRIDAD DE DATOS v1"
      puts "  Pipeline: Google Sheets → SheetRowProcessor → PostgreSQL"
      puts "  #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}"
      puts SEPARATOR

      results = {}
      results[:prueba_1] = prueba_1_parse_currency
      results[:prueba_2] = prueba_2_parse_decimal
      results[:prueba_3] = prueba_3_parse_date
      results[:prueba_4] = prueba_4_parse_boolean
      results[:prueba_5] = prueba_5_parsed_coords
      results[:prueba_6] = prueba_6_col_helper
      results[:prueba_7] = prueba_7_full_dirty_row_mapping
      results[:prueba_8] = prueba_8_blank_cells_to_null
      results[:prueba_9] = prueba_9_mirror_clear_existing
      results[:prueba_10] = prueba_10_empty_row_skipped
      results[:prueba_11] = prueba_11_upsert_no_duplicates
      results[:prueba_12] = prueba_12_crm_immunity_guard
      results[:prueba_13] = prueba_13_crm_data_survives_resync
      results[:prueba_14] = prueba_14_extreme_currency
      results[:prueba_15] = prueba_15_static_crm_regression

      print_summary(results)
    end

    # ── Assertion Helpers ──────────────────────────────────────────────────────
    def assert_eq(actual, expected, label)
      self.total_assertions += 1
      if actual == expected
        self.passed_assertions += 1
        puts "    #{PASS} #{label}"
      else
        self.failed_assertions += 1
        failures << "[FAIL] #{label}: expected=#{expected.inspect}, got=#{actual.inspect}"
        puts "    #{FAIL} #{label}: expected #{expected.inspect}, got #{actual.inspect}"
      end
    end

    def assert_nil_val(actual, label)
      assert_eq(actual, nil, label)
    end

    def assert_present(actual, label)
      self.total_assertions += 1
      if actual.present?
        self.passed_assertions += 1
        puts "    #{PASS} #{label}"
      else
        self.failed_assertions += 1
        failures << "[FAIL] #{label}: expected present, got #{actual.inspect}"
        puts "    #{FAIL} #{label}: expected present, got #{actual.inspect}"
      end
    end

    def assert_raises(exception_class, label, &block)
      self.total_assertions += 1
      begin
        block.call
        self.failed_assertions += 1
        failures << "[FAIL] #{label}: expected #{exception_class} but no error raised"
        puts "    #{FAIL} #{label}: No exception raised"
      rescue => e
        if e.is_a?(exception_class)
          self.passed_assertions += 1
          puts "    #{PASS} #{label}"
        else
          self.failed_assertions += 1
          failures << "[FAIL] #{label}: expected #{exception_class}, got #{e.class}"
          puts "    #{FAIL} #{label}: expected #{exception_class}, got #{e.class}: #{e.message.truncate(80)}"
        end
      end
    end

    def isolated_test(label)
      ActiveRecord::Base.connection.execute("SAVEPOINT audit_#{label}")
      begin
        result = yield
        ActiveRecord::Base.connection.execute("RELEASE SAVEPOINT audit_#{label}")
        result
      rescue => e
        ActiveRecord::Base.connection.execute("ROLLBACK TO SAVEPOINT audit_#{label}")
        raise e
      end
    end

    # ── Helper: Construir fila con datos sucios ──────────────────────────────
    def dirty_sheet_row
      row = Array.new(80, nil)
      row[SheetColumnMap::STATE]          = "  FL "
      row[SheetColumnMap::COUNTY]         = " Escambia  "
      row[SheetColumnMap::PARCEL_ID]      = " 01-2S-30-0000-001-002 "
      row[SheetColumnMap::AUCTION_DATE]   = " 05/15/2026 "
      row[SheetColumnMap::MARKET_VALUE]   = "$125,000"
      row[SheetColumnMap::OPENING_BID]    = " $25,000.50 "
      row[SheetColumnMap::ASSESSED_VALUE] = "95000"
      row[SheetColumnMap::ESTIMATED_SALE_VALUE] = "$85,000"
      row[SheetColumnMap::LOT_AREA_ACRES] = " 2.5000 "
      row[SheetColumnMap::SQFT_LOT]       = "10,890"
      row[SheetColumnMap::SQFT_LIVING]    = " 1,500.75 "
      row[SheetColumnMap::MINIMUM_LOT_SIZE] = " No minimum lot area unless prescribed by use. "
      row[SheetColumnMap::ZONING]         = " R-1 "
      row[SheetColumnMap::JURISDICTION]   = "ESCAMBIA COUNTY UNINCORPORATED "
      row[SheetColumnMap::LAND_USE]       = " Single Family "
      row[SheetColumnMap::OWNER_NAME]     = " John Doe "
      row[SheetColumnMap::OWNER_MAIL_ADDRESS] = " 123 Main St, Pensacola FL 32501 "
      row[SheetColumnMap::PROPERTY_ADDRESS] = " 456 Oak Ave "
      row[SheetColumnMap::ADDRESS]        = " 456 Oak Ave "
      row[SheetColumnMap::ZIP]            = " 32501 "
      row[SheetColumnMap::CITY]           = " Pensacola "
      row[SheetColumnMap::LEGAL_DESCRIPTION] = " LOT 2 BLK A EASTVIEW ESTATES "
      row[SheetColumnMap::CRIME_LEVEL]    = " Low "
      row[SheetColumnMap::HOMESTEAD_FLAG] = " Investor "
      row[SheetColumnMap::ELECTRIC]       = " yes "
      row[SheetColumnMap::WATER]          = "Yes"
      row[SheetColumnMap::SEWER]          = " YES "
      row[SheetColumnMap::LOT_SHAPE]      = " Flat "
      row[SheetColumnMap::HOA]            = " no "
      row[SheetColumnMap::WETLANDS_RAW]   = " yes "
      row[SheetColumnMap::FEMA_RISK_LEVEL] = " Zone X (Minimal risk) "
      row[SheetColumnMap::FEMA_NOTES]     = " Outside 500-year floodplain "
      row[SheetColumnMap::FEMA_URL]       = " https://msc.fema.gov/portal/search?AddressQuery=32501 "
      row[SheetColumnMap::COORDINATES_RAW] = " 30.452145, -87.270564 "
      row[SheetColumnMap::REGRID_URL]     = " https://app.regrid.com/us/fl/escambia/01-2S "
      row[SheetColumnMap::GIS_IMAGE_URL]  = " https://gis.escambiaclerk.com/map/01-2S-30.png "
      row[SheetColumnMap::GOOGLE_MAPS_URL] = " https://maps.google.com/?q=30.452145,-87.270564 "
      row[SheetColumnMap::PROPERTY_IMAGE_URL] = " https://storage.googleapis.com/images/01-2S.jpg "
      row[SheetColumnMap::CLERK_URL]      = " https://escambiaclerk.com/search "
      row[SheetColumnMap::TAX_COLLECTOR_URL] = " https://escambiatax.com/search "
      row
    end

    # ══════════════════════════════════════════════════════════════════════════
    # PRUEBA 1: parse_currency — 10 formatos sucios
    # ══════════════════════════════════════════════════════════════════════════
    def prueba_1_parse_currency
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 1: parse_currency — Formatos de moneda sucios     │"
      puts "└─────────────────────────────────────────────────────────────┘"

      p = SheetRowProcessor.new([])

      assert_eq p.send(:parse_currency, "$25,000"),          BigDecimal("25000"),      "$25,000 → 25000"
      assert_eq p.send(:parse_currency, "25000"),            BigDecimal("25000"),      "25000 → 25000"
      assert_eq p.send(:parse_currency, "$25,000.50"),       BigDecimal("25000.50"),   "$25,000.50 → 25000.50"
      assert_eq p.send(:parse_currency, " $25,000 "),        BigDecimal("25000"),      "' $25,000 ' → 25000 (espacios)"
      assert_eq p.send(:parse_currency, "$1,234,567.89"),    BigDecimal("1234567.89"), "$1,234,567.89 → millones"
      assert_eq p.send(:parse_currency, "$0"),               BigDecimal("0"),          "$0 → 0"
      assert_eq p.send(:parse_currency, "$0.00"),            BigDecimal("0"),          "$0.00 → 0"
      assert_nil_val p.send(:parse_currency, ""),             "'' → nil"
      assert_nil_val p.send(:parse_currency, nil),            "nil → nil"
      assert_nil_val p.send(:parse_currency, "   "),          "'   ' → nil"
      assert_nil_val p.send(:parse_currency, "N/A"),          "N/A → nil"
      assert_nil_val p.send(:parse_currency, "TBD"),          "TBD → nil"
      assert_nil_val p.send(:parse_currency, "pending"),      "pending → nil"

      { status: :pass }
    end

    # ══════════════════════════════════════════════════════════════════════════
    # PRUEBA 2: parse_decimal — Formatos de área/superficie
    # ══════════════════════════════════════════════════════════════════════════
    def prueba_2_parse_decimal
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 2: parse_decimal — Formatos de decimales sucios   │"
      puts "└─────────────────────────────────────────────────────────────┘"

      p = SheetRowProcessor.new([])

      assert_eq p.send(:parse_decimal, "10,890"),         BigDecimal("10890"),     "10,890 → 10890"
      assert_eq p.send(:parse_decimal, " 1,500.75 "),     BigDecimal("1500.75"),   "' 1,500.75 ' → 1500.75"
      assert_eq p.send(:parse_decimal, "2.5000"),         BigDecimal("2.5"),       "2.5000 → 2.5"
      assert_eq p.send(:parse_decimal, "0.25"),           BigDecimal("0.25"),      "0.25 → 0.25"
      assert_nil_val p.send(:parse_decimal, ""),           "'' → nil"
      assert_nil_val p.send(:parse_decimal, nil),          "nil → nil"
      assert_nil_val p.send(:parse_decimal, "N/A"),        "N/A → nil"

      { status: :pass }
    end

    # ══════════════════════════════════════════════════════════════════════════
    # PRUEBA 3: parse_date — Formatos de fecha
    # ══════════════════════════════════════════════════════════════════════════
    def prueba_3_parse_date
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 3: parse_date — Formatos de fecha                 │"
      puts "└─────────────────────────────────────────────────────────────┘"

      p = SheetRowProcessor.new([])

      assert_eq p.send(:parse_date, "05/15/2026"),       Date.new(2026, 5, 15),  "05/15/2026 → MM/DD/YYYY"
      assert_eq p.send(:parse_date, "2026-05-15"),       Date.new(2026, 5, 15),  "2026-05-15 → ISO fallback"
      assert_nil_val p.send(:parse_date, ""),             "'' → nil"
      assert_nil_val p.send(:parse_date, nil),            "nil → nil"
      assert_nil_val p.send(:parse_date, "not-a-date"),   "garbage → nil"

      { status: :pass }
    end

    # ══════════════════════════════════════════════════════════════════════════
    # PRUEBA 4: parse_boolean — yes/no/variaciones
    # ══════════════════════════════════════════════════════════════════════════
    def prueba_4_parse_boolean
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 4: parse_boolean — Booleanos sucios               │"
      puts "└─────────────────────────────────────────────────────────────┘"

      p = SheetRowProcessor.new([])

      assert_eq p.send(:parse_boolean, "yes"),       true,   "yes → true"
      assert_eq p.send(:parse_boolean, "Yes"),       true,   "Yes → true"
      assert_eq p.send(:parse_boolean, " YES "),     true,   "' YES ' → true"
      assert_eq p.send(:parse_boolean, " yes "),     true,   "' yes ' → true"
      assert_eq p.send(:parse_boolean, "no"),        false,  "no → false"
      assert_eq p.send(:parse_boolean, "No"),        false,  "No → false"
      assert_eq p.send(:parse_boolean, " NO "),      false,  "' NO ' → false"
      assert_nil_val p.send(:parse_boolean, ""),      "'' → nil"
      assert_nil_val p.send(:parse_boolean, nil),     "nil → nil"

      { status: :pass }
    end

    # ══════════════════════════════════════════════════════════════════════════
    # PRUEBA 5: parsed_coords — Coordenadas
    # ══════════════════════════════════════════════════════════════════════════
    def prueba_5_parsed_coords
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 5: parsed_coords — Coordenadas                    │"
      puts "└─────────────────────────────────────────────────────────────┘"

      # Con coordenadas válidas
      p1 = SheetRowProcessor.new(dirty_sheet_row)
      coords = p1.send(:parsed_coords)
      assert_eq coords[:latitude],  BigDecimal("30.452145"),  "lat = 30.452145"
      assert_eq coords[:longitude], BigDecimal("-87.270564"), "lng = -87.270564"

      # Celda vacía
      row_empty = Array.new(80, nil)
      row_empty[SheetColumnMap::COORDINATES_RAW] = ""
      p2 = SheetRowProcessor.new(row_empty)
      coords2 = p2.send(:parsed_coords)
      assert_nil_val coords2[:latitude],  "celda vacía → lat nil"
      assert_nil_val coords2[:longitude], "celda vacía → lng nil"

      # Basura
      row_garbage = Array.new(80, nil)
      row_garbage[SheetColumnMap::COORDINATES_RAW] = "garbage data"
      p3 = SheetRowProcessor.new(row_garbage)
      coords3 = p3.send(:parsed_coords)
      assert_nil_val coords3[:latitude],  "basura → lat nil"
      assert_nil_val coords3[:longitude], "basura → lng nil"

      # SIEMPRE retorna ambas keys
      row_nil = Array.new(80, nil)
      p4 = SheetRowProcessor.new(row_nil)
      coords4 = p4.send(:parsed_coords)
      assert_eq coords4.key?(:latitude),  true, "hash SIEMPRE tiene :latitude key"
      assert_eq coords4.key?(:longitude), true, "hash SIEMPRE tiene :longitude key"

      { status: :pass }
    end

    # ══════════════════════════════════════════════════════════════════════════
    # PRUEBA 6: col() helper — Sanitización de celdas
    # ══════════════════════════════════════════════════════════════════════════
    def prueba_6_col_helper
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 6: col() helper — Sanitización de celdas          │"
      puts "└─────────────────────────────────────────────────────────────┘"

      assert_nil_val SheetRowProcessor.new([""]).send(:col, 0),         "'' → nil"
      assert_nil_val SheetRowProcessor.new(["   "]).send(:col, 0),      "'   ' → nil"
      assert_eq      SheetRowProcessor.new(["  hello  "]).send(:col, 0), "hello", "'  hello  ' → 'hello'"
      assert_nil_val SheetRowProcessor.new(["a", "b"]).send(:col, 99),  "out-of-bounds → nil"

      { status: :pass }
    end

    # ══════════════════════════════════════════════════════════════════════════
    # PRUEBA 7: Mapeo exhaustivo de datos premium — Fila sucia completa
    # ══════════════════════════════════════════════════════════════════════════
    def prueba_7_full_dirty_row_mapping
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 7: Mapeo Premium Completo — Fila dirty → BD       │"
      puts "└─────────────────────────────────────────────────────────────┘"

      ActiveRecord::Base.transaction do
        result = SheetRowProcessor.process(dirty_sheet_row)
        assert_eq result, :added, "Resultado = :added"

        parcel = Parcel.find_by!(
          state: "FL", county: "Escambia", parcel_id: "01-2S-30-0000-001-002"
        )

        # Identificación
        assert_eq parcel.state,            "FL",                        "state"
        assert_eq parcel.county,           "Escambia",                  "county"
        assert_eq parcel.parcel_id,        "01-2S-30-0000-001-002",     "parcel_id"
        assert_eq parcel.address,          "456 Oak Ave",               "address"
        assert_eq parcel.zip,              "32501",                     "zip"
        assert_eq parcel.city,             "Pensacola",                 "city"
        assert_eq parcel.owner_name,       "John Doe",                  "owner_name"

        # Financiero
        assert_eq parcel.market_value,          BigDecimal("125000"),    "market_value"
        assert_eq parcel.opening_bid,           BigDecimal("25000.50"), "opening_bid"
        assert_eq parcel.assessed_value,        BigDecimal("95000"),     "assessed_value"
        assert_eq parcel.estimated_sale_value,  BigDecimal("85000"),     "estimated_sale_value"

        # Price Per Acre: 25000.50 / 2.5 = 10000.20
        assert_eq parcel.price_per_acre,        BigDecimal("10000.20"), "price_per_acre calculado"

        # Físico
        assert_eq parcel.lot_area_acres,  BigDecimal("2.5"),       "lot_area_acres"
        assert_eq parcel.sqft_lot,        BigDecimal("10890"),     "sqft_lot"
        assert_eq parcel.sqft_living,     BigDecimal("1500.75"),   "sqft_living"

        # Premium: Zonificación, Jurisdicción, etc.
        assert_eq parcel.zoning,          "R-1",                   "zoning"
        assert_eq parcel.jurisdiction,    "ESCAMBIA COUNTY UNINCORPORATED", "jurisdiction"
        assert_eq parcel.land_use,        "Single Family",         "land_use"
        assert_eq parcel.homestead_flag,  "Investor",              "homestead_flag"
        assert_eq parcel.crime_level,     "Low",                   "crime_level"

        # Utilities
        assert_eq parcel.electric,        "yes",                   "electric"
        assert_eq parcel.water,           "Yes",                   "water"
        assert_eq parcel.sewer,           "YES",                   "sewer"
        assert_eq parcel.lot_shape,       "Flat",                  "lot_shape"
        assert_eq parcel.hoa,             "no",                    "hoa"

        # FEMA
        assert_eq parcel.wetlands,        true,                    "wetlands"
        assert_eq parcel.fema_risk_level, "Zone X (Minimal risk)", "fema_risk_level"
        assert_eq parcel.fema_notes,      "Outside 500-year floodplain", "fema_notes"
        assert_present parcel.fema_url,                            "fema_url presente"

        # Coordenadas
        assert_eq parcel.latitude,        BigDecimal("30.452145"),  "latitude"
        assert_eq parcel.longitude,       BigDecimal("-87.270564"), "longitude"

        # Links externos
        assert_present parcel.regrid_url,          "regrid_url presente"
        assert_present parcel.gis_image_url,       "gis_image_url presente"
        assert_present parcel.google_maps_url,     "google_maps_url presente"
        assert_present parcel.property_image_url,  "property_image_url presente"
        assert_present parcel.clerk_url,           "clerk_url presente"
        assert_present parcel.tax_collector_url,   "tax_collector_url presente"

        # Metadata
        assert_eq parcel.data_source,     "google_sheets",         "data_source"
        assert_present parcel.last_synced_at,                      "last_synced_at presente"

        assert_eq parcel.legal_description, "LOT 2 BLK A EASTVIEW ESTATES", "legal_description"

        raise ActiveRecord::Rollback
      end

      { status: :pass }
    end

    # ══════════════════════════════════════════════════════════════════════════
    # PRUEBA 8: Celdas vacías → NULL en PostgreSQL
    # ══════════════════════════════════════════════════════════════════════════
    def prueba_8_blank_cells_to_null
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 8: Celdas vacías → NULL en PostgreSQL             │"
      puts "└─────────────────────────────────────────────────────────────┘"

      ActiveRecord::Base.transaction do
        row = Array.new(80, nil)
        row[SheetColumnMap::STATE]     = "FL"
        row[SheetColumnMap::COUNTY]    = "Orange"
        row[SheetColumnMap::PARCEL_ID] = "99-0001-BLANK"
        row[SheetColumnMap::AUCTION_DATE] = "06/01/2026"

        result = SheetRowProcessor.process(row)
        assert_eq result, :added, "Parcela con campos vacíos creada"

        parcel = Parcel.find_by!(state: "FL", county: "Orange", parcel_id: "99-0001-BLANK")

        assert_nil_val parcel.opening_bid,         "opening_bid nil"
        assert_nil_val parcel.assessed_value,      "assessed_value nil"
        assert_nil_val parcel.market_value,        "market_value nil"
        assert_nil_val parcel.estimated_sale_value, "estimated_sale_value nil"
        assert_nil_val parcel.lot_area_acres,      "lot_area_acres nil"
        assert_nil_val parcel.sqft_lot,            "sqft_lot nil"
        assert_nil_val parcel.sqft_living,         "sqft_living nil"
        assert_nil_val parcel.zoning,              "zoning nil"
        assert_nil_val parcel.jurisdiction,        "jurisdiction nil"
        assert_nil_val parcel.land_use,            "land_use nil"
        assert_nil_val parcel.latitude,            "latitude nil"
        assert_nil_val parcel.longitude,           "longitude nil"
        assert_nil_val parcel.wetlands,            "wetlands nil"
        assert_nil_val parcel.fema_risk_level,     "fema_risk_level nil"
        assert_nil_val parcel.electric,            "electric nil"
        assert_nil_val parcel.hoa,                 "hoa nil"
        assert_nil_val parcel.price_per_acre,      "price_per_acre nil"

        raise ActiveRecord::Rollback
      end

      { status: :pass }
    end

    # ══════════════════════════════════════════════════════════════════════════
    # PRUEBA 9: Espejo Infalible — Datos existentes se limpian
    # ══════════════════════════════════════════════════════════════════════════
    def prueba_9_mirror_clear_existing
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 9: Espejo Infalible — Datos existentes se limpian │"
      puts "└─────────────────────────────────────────────────────────────┘"

      ActiveRecord::Base.transaction do
        # Paso 1: Crear parcela con datos completos
        SheetRowProcessor.process(dirty_sheet_row)
        parcel = Parcel.find_by!(state: "FL", county: "Escambia", parcel_id: "01-2S-30-0000-001-002")

        assert_eq parcel.opening_bid, BigDecimal("25000.50"), "Tiene opening_bid ANTES"
        assert_eq parcel.zoning,      "R-1",                  "Tiene zoning ANTES"
        assert_eq parcel.latitude,    BigDecimal("30.452145"), "Tiene lat ANTES"

        # Paso 2: Procesar misma parcela con campos vacíos
        cleared_row = Array.new(80, nil)
        cleared_row[SheetColumnMap::STATE]     = "FL"
        cleared_row[SheetColumnMap::COUNTY]    = "Escambia"
        cleared_row[SheetColumnMap::PARCEL_ID] = "01-2S-30-0000-001-002"
        cleared_row[SheetColumnMap::AUCTION_DATE] = "05/15/2026"

        result = SheetRowProcessor.process(cleared_row)
        assert_eq result, :updated, "Retorna :updated"

        parcel.reload

        assert_nil_val parcel.opening_bid,     "opening_bid limpiado"
        assert_nil_val parcel.latitude,        "latitude limpiado"
        assert_nil_val parcel.longitude,       "longitude limpiado"
        assert_nil_val parcel.zoning,          "zoning limpiado"
        assert_nil_val parcel.assessed_value,  "assessed_value limpiado"
        assert_nil_val parcel.market_value,    "market_value limpiado"
        assert_nil_val parcel.wetlands,        "wetlands limpiado"
        assert_nil_val parcel.fema_risk_level, "fema_risk_level limpiado"
        assert_nil_val parcel.electric,        "electric limpiado"
        assert_nil_val parcel.hoa,             "hoa limpiado"

        raise ActiveRecord::Rollback
      end

      { status: :pass }
    end

    # ══════════════════════════════════════════════════════════════════════════
    # PRUEBA 10: Fila vacía → :skipped
    # ══════════════════════════════════════════════════════════════════════════
    def prueba_10_empty_row_skipped
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 10: Fila vacía → :skipped                        │"
      puts "└─────────────────────────────────────────────────────────────┘"

      result = SheetRowProcessor.process(Array.new(80, nil))
      assert_eq result, :skipped, "Fila vacía → :skipped"

      row_whitespace = Array.new(80, nil)
      row_whitespace[SheetColumnMap::PARCEL_ID] = "   "
      row_whitespace[SheetColumnMap::ADDRESS] = "   "
      result2 = SheetRowProcessor.process(row_whitespace)
      assert_eq result2, :skipped, "Fila solo-whitespace → :skipped"

      { status: :pass }
    end

    # ══════════════════════════════════════════════════════════════════════════
    # PRUEBA 11: Upsert no duplica (segunda pasada → :updated)
    # ══════════════════════════════════════════════════════════════════════════
    def prueba_11_upsert_no_duplicates
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 11: Upsert no duplica — segunda pasada            │"
      puts "└─────────────────────────────────────────────────────────────┘"

      ActiveRecord::Base.transaction do
        SheetRowProcessor.process(dirty_sheet_row)
        count_after_first = Parcel.where(
          state: "FL", county: "Escambia", parcel_id: "01-2S-30-0000-001-002"
        ).count

        result2 = SheetRowProcessor.process(dirty_sheet_row)
        count_after_second = Parcel.where(
          state: "FL", county: "Escambia", parcel_id: "01-2S-30-0000-001-002"
        ).count

        assert_eq count_after_first,  1, "1 parcela después del 1er proceso"
        assert_eq count_after_second, 1, "Sigue 1 parcela después del 2do proceso"
        assert_eq result2, :updated,     "2da pasada retorna :updated"

        raise ActiveRecord::Rollback
      end

      { status: :pass }
    end

    # ══════════════════════════════════════════════════════════════════════════
    # PRUEBA 12: CRM Immunity Guard — Bloquea campos protegidos
    # ══════════════════════════════════════════════════════════════════════════
    def prueba_12_crm_immunity_guard
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 12: CRM Immunity Guard                            │"
      puts "└─────────────────────────────────────────────────────────────┘"

      processor = SheetRowProcessor.new(dirty_sheet_row)

      # Guard bloquea campos protegidos
      %w[parcel_user_tags parcel_user_notes user_tags user_notes].each do |col_name|
        assert_raises(ActiveRecord::RecordNotSaved, "Guard bloquea #{col_name}") do
          processor.send(:enforce_crm_immunity!, { col_name.to_sym => "injected" })
        end
      end

      # Guard permite atributos limpios
      begin
        processor.send(:enforce_crm_immunity!, {
          state: "FL", county: "Escambia", opening_bid: BigDecimal("25000")
        })
        self.total_assertions += 1
        self.passed_assertions += 1
        puts "    #{PASS} Guard permite atributos limpios"
      rescue => e
        self.total_assertions += 1
        self.failed_assertions += 1
        puts "    #{FAIL} Guard bloqueó atributos limpios: #{e.message.truncate(80)}"
      end

      { status: :pass }
    end

    # ══════════════════════════════════════════════════════════════════════════
    # PRUEBA 13: CRM Data sobrevive al re-sync
    # ══════════════════════════════════════════════════════════════════════════
    def prueba_13_crm_data_survives_resync
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 13: CRM Data sobrevive al re-sync                 │"
      puts "└─────────────────────────────────────────────────────────────┘"

      ActiveRecord::Base.transaction do
        # Crear parcela
        SheetRowProcessor.process(dirty_sheet_row)
        parcel = Parcel.find_by!(state: "FL", county: "Escambia", parcel_id: "01-2S-30-0000-001-002")

        # Crear datos CRM del usuario
        user = User.create!(
          email: "crm-audit-#{SecureRandom.hex(4)}@test.local",
          password: "TestPassword123!"
        )
        ParcelUserTag.upsert_for!(user: user, parcel: parcel, tag: "target")
        ParcelUserNote.create!(user: user, parcel: parcel, body: "Great investment opportunity")

        # Re-sync
        SheetRowProcessor.process(dirty_sheet_row)

        # Verificar inmunidad
        tags = ParcelUserTag.where(user: user, parcel: parcel)
        notes = ParcelUserNote.where(user: user, parcel: parcel)

        assert_eq tags.count,        1,                         "Tag sobrevivió re-sync"
        assert_eq tags.first.tag,    "target",                  "Valor del tag intacto"
        assert_eq notes.count,       1,                         "Nota sobrevivió re-sync"
        assert_eq notes.first.body,  "Great investment opportunity", "Contenido de nota intacto"

        raise ActiveRecord::Rollback
      end

      { status: :pass }
    end

    # ══════════════════════════════════════════════════════════════════════════
    # PRUEBA 14: Formatos de moneda extremos
    # ══════════════════════════════════════════════════════════════════════════
    def prueba_14_extreme_currency
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 14: Formatos de moneda extremos                   │"
      puts "└─────────────────────────────────────────────────────────────┘"

      ActiveRecord::Base.transaction do
        row = Array.new(80, nil)
        row[SheetColumnMap::STATE]       = "FL"
        row[SheetColumnMap::COUNTY]      = "Escambia"
        row[SheetColumnMap::PARCEL_ID]   = "EXTREME-CURRENCY-001"
        row[SheetColumnMap::AUCTION_DATE] = "07/20/2026"
        row[SheetColumnMap::OPENING_BID]  = "$1,234,567.89"
        row[SheetColumnMap::ASSESSED_VALUE] = "0"
        row[SheetColumnMap::MARKET_VALUE]   = "  $0.00  "
        row[SheetColumnMap::ESTIMATED_SALE_VALUE] = "N/A"
        row[SheetColumnMap::LOT_AREA_ACRES] = "0.25"

        result = SheetRowProcessor.process(row)
        assert_eq result, :added, "Parcela extrema creada"

        parcel = Parcel.find_by!(state: "FL", county: "Escambia", parcel_id: "EXTREME-CURRENCY-001")

        assert_eq parcel.opening_bid,          BigDecimal("1234567.89"), "Millones parseados"
        assert_eq parcel.assessed_value,       BigDecimal("0"),          "Cero explícito = 0"
        assert_eq parcel.market_value,         BigDecimal("0"),          "$0.00 = 0"
        assert_nil_val parcel.estimated_sale_value,                      "N/A → nil"

        raise ActiveRecord::Rollback
      end

      { status: :pass }
    end

    # ══════════════════════════════════════════════════════════════════════════
    # PRUEBA 15: Regresión estática — Código fuente no contiene CRM keys
    # ══════════════════════════════════════════════════════════════════════════
    def prueba_15_static_crm_regression
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 15: Regresión estática — Sin CRM keys en attrs    │"
      puts "└─────────────────────────────────────────────────────────────┘"

      source = File.read(Rails.root.join("app/services/sheet_row_processor.rb"))

      # Buscar en la sección del hash de attrs (después de "attrs = {")
      attrs_section = source.split("attrs = {").last.split("enforce_crm_immunity!").first

      SheetRowProcessor::CRM_IMMUNE_COLUMNS.each do |col_name|
        self.total_assertions += 1
        if attrs_section.include?("#{col_name}:")
          self.failed_assertions += 1
          failures << "[FAIL] Código contiene '#{col_name}:' en attrs hash"
          puts "    #{FAIL} '#{col_name}:' encontrado en attrs hash"
        else
          self.passed_assertions += 1
          puts "    #{PASS} '#{col_name}:' NO está en attrs hash"
        end
      end

      { status: :pass }
    end

    # ── RESUMEN ──────────────────────────────────────────────────────────────
    private

    def print_summary(results)
      puts "\n#{SEPARATOR}"
      puts "  📋 RESUMEN DE AUDITORÍA DE INTEGRIDAD"
      puts SEPARATOR

      puts "\n  Total de aserciones: #{total_assertions}"
      puts "  Pasaron:             #{passed_assertions} ✅"
      puts "  Fallaron:            #{failed_assertions} ❌"

      if failures.any?
        puts "\n  ── FALLOS ─────────────────────────────────────────────────"
        failures.each { |f| puts "  #{f}" }
      end

      pct = total_assertions > 0 ? (passed_assertions.to_f / total_assertions * 100).round(1) : 0
      puts "\n  ── VEREDICTO: #{pct}% de aserciones pasaron"

      if failed_assertions == 0
        puts "  🏆 INTEGRIDAD PERFECTA — El espejo Google Sheets ↔ PostgreSQL es INFALIBLE"
      else
        puts "  🚨 HAY BRECHAS DE INTEGRIDAD — Revisar los fallos arriba"
      end
      puts SEPARATOR
    end
  end
end

DataIntegrityAudit.run_all
