# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════════════
# QA: VALIDACIÓN DEL SHIFT +3 POR COLUMNAS DE ELEVACIÓN
# ═══════════════════════════════════════════════════════════════════════════════
#
# Ejecutar con:  rails runner test/scripts/column_shift_qa.rb
#
# Valida 4 áreas críticas:
#   1. Consistencia interna del SheetColumnMap (sin duplicados, sin gaps)
#   2. Mapeo posicional correcto: fila simulada del Sheet → campos BD
#   3. Columnas de elevación correctamente ignoradas (no contaminan datos)
#   4. Rangos del GoogleSheetsImporter cubren todas las columnas
#
# Todas las pruebas de BD usan TRANSACTION + ROLLBACK.
# ═══════════════════════════════════════════════════════════════════════════════

module ColumnShiftQA
  PASS = "✅ PASS"
  FAIL = "❌ FAIL"
  SEP  = "═" * 72

  class << self
    attr_accessor :total, :passed, :failed, :failures

    def run_all
      self.total = 0; self.passed = 0; self.failed = 0; self.failures = []

      puts "\n#{SEP}"
      puts "  🔬 QA: SHIFT +3 — Columnas de Elevación (2026-04-21)"
      puts "  #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}"
      puts SEP

      qa_1_no_duplicate_indices
      qa_2_elevation_positions
      qa_3_shifted_positions_correct
      qa_4_simulated_row_mapping
      qa_5_elevation_not_persisted
      qa_6_importer_range_coverage
      qa_7_ignored_arrays_consistent
      qa_8_full_pipeline_e2e

      print_summary
    end

    # ── Helpers ────────────────────────────────────────────────────────────
    def assert_eq(actual, expected, label)
      self.total += 1
      if actual == expected
        self.passed += 1
        puts "    #{PASS} #{label}"
      else
        self.failed += 1
        failures << "[FAIL] #{label}: expected=#{expected.inspect}, got=#{actual.inspect}"
        puts "    #{FAIL} #{label}: expected #{expected.inspect}, got #{actual.inspect}"
      end
    end

    def assert_true(val, label)  = assert_eq(val, true, label)
    def assert_nil_val(val, label) = assert_eq(val, nil, label)
    def assert_present(val, label)
      self.total += 1
      if val.present?
        self.passed += 1; puts "    #{PASS} #{label}"
      else
        self.failed += 1; failures << "[FAIL] #{label}: blank"; puts "    #{FAIL} #{label}: blank"
      end
    end

    # ════════════════════════════════════════════════════════════════════════
    # QA 1: Sin índices duplicados en SheetColumnMap
    # ════════════════════════════════════════════════════════════════════════
    def qa_1_no_duplicate_indices
      puts "\n┌────────────────────────────────────────────────────────────┐"
      puts "│  QA 1: Sin índices duplicados en SheetColumnMap          │"
      puts "└────────────────────────────────────────────────────────────┘"

      # Recopilar todas las constantes con valor Integer
      constants = SheetColumnMap.constants.select { |c|
        v = SheetColumnMap.const_get(c)
        v.is_a?(Integer)
      }

      index_map = {}
      constants.each do |c|
        v = SheetColumnMap.const_get(c)
        next if c == :ADDRESS # ADDRESS es alias de PROPERTY_ADDRESS (ambos = 22)
        (index_map[v] ||= []) << c
      end

      duplicates = index_map.select { |_, names| names.size > 1 }
      assert_eq duplicates, {}, "Sin duplicados (excepto ADDRESS alias)"

      puts "    📊 #{constants.size} constantes verificadas"
    end

    # ════════════════════════════════════════════════════════════════════════
    # QA 2: Columnas de elevación en posiciones 34, 35, 36
    # ════════════════════════════════════════════════════════════════════════
    def qa_2_elevation_positions
      puts "\n┌────────────────────────────────────────────────────────────┐"
      puts "│  QA 2: Elevación en posiciones 34-36 (ignoradas)         │"
      puts "└────────────────────────────────────────────────────────────┘"

      # Verificar que 34, 35, 36 NO son constantes con nombre
      mapped = SheetColumnMap.constants.select { |c|
        SheetColumnMap.const_get(c).is_a?(Integer)
      }.map { |c| SheetColumnMap.const_get(c) }

      assert_true !mapped.include?(34) || SheetColumnMap.constants.none? { |c|
        SheetColumnMap.const_get(c) == 34 && c != :ADDRESS
      }, "Pos 34 no mapeada a campo de BD"

      # 34-36 deben estar en IGNORED_INTERNAL
      assert_true SheetColumnMap::IGNORED_INTERNAL.include?(34), "34 (High Elev) en IGNORED"
      assert_true SheetColumnMap::IGNORED_INTERNAL.include?(35), "35 (Low Elev) en IGNORED"
      assert_true SheetColumnMap::IGNORED_INTERNAL.include?(36), "36 (Elev Diff) en IGNORED"
    end

    # ════════════════════════════════════════════════════════════════════════
    # QA 3: Posiciones post-shift correctas
    # ════════════════════════════════════════════════════════════════════════
    def qa_3_shifted_positions_correct
      puts "\n┌────────────────────────────────────────────────────────────┐"
      puts "│  QA 3: Posiciones post-shift (+3) correctas              │"
      puts "└────────────────────────────────────────────────────────────┘"

      # Pre-shift positions (antes del cambio) → Post-shift (actual)
      expected = {
        LOT_SHAPE:           37,  # was 34
        COORDINATES_RAW:     39,  # was 36
        WETLANDS_RAW:        40,  # was 37
        FEMA_NOTES:          41,  # was 38
        FEMA_URL:            42,  # was 39
        FEMA_RISK_LEVEL:     43,  # was 40
        PROPERTY_IMAGE_URL:  44,  # was 41
        HOA:                 46,  # was 43
        ESTIMATED_SALE_VALUE: 71, # was 68
        CLERK_URL:           79,  # was 76
        TAX_COLLECTOR_URL:   80,  # was 77
      }

      expected.each do |const, pos|
        actual = SheetColumnMap.const_get(const)
        assert_eq actual, pos, "#{const} = #{pos}"
      end

      # Pre-shift positions que NO cambiaron (antes de pos 34)
      unchanged = {
        STATE: 0, COUNTY: 1, SALE_VENUE: 2, PARCEL_ID: 3,
        AUCTION_DATE: 7, MARKET_VALUE: 8, OPENING_BID: 9,
        ASSESSED_VALUE: 10, ELECTRIC: 31, WATER: 32, SEWER: 33,
      }
      unchanged.each do |const, pos|
        actual = SheetColumnMap.const_get(const)
        assert_eq actual, pos, "#{const} = #{pos} (sin cambio)"
      end
    end

    # ════════════════════════════════════════════════════════════════════════
    # QA 4: Fila simulada → campos correctos en el Processor
    # ════════════════════════════════════════════════════════════════════════
    def qa_4_simulated_row_mapping
      puts "\n┌────────────────────────────────────────────────────────────┐"
      puts "│  QA 4: Fila simulada → mapeo posicional correcto         │"
      puts "└────────────────────────────────────────────────────────────┘"

      # Construir fila con datos en las posiciones EXACTAS del Sheet real
      row = Array.new(83, nil)

      # Datos pre-elevación (no cambiaron)
      row[0]  = "FL"                    # STATE
      row[1]  = "Polk"                  # COUNTY
      row[2]  = "Online"                # SALE_VENUE
      row[3]  = "QA-SHIFT-001"          # PARCEL_ID
      row[7]  = "06/15/2026"            # AUCTION_DATE
      row[8]  = "$200,000"              # MARKET_VALUE
      row[9]  = "$50,000"               # OPENING_BID
      row[10] = "$150,000"              # ASSESSED_VALUE
      row[11] = "5.0"                   # LOT_AREA_ACRES
      row[12] = "217,800"               # SQFT_LOT
      row[22] = "123 Test Rd"           # PROPERTY_ADDRESS
      row[23] = "33801"                 # ZIP
      row[24] = "Lakeland"              # CITY
      row[31] = "yes"                   # ELECTRIC
      row[32] = "yes"                   # WATER
      row[33] = "no"                    # SEWER

      # Columnas de elevación (DEBEN SER IGNORADAS)
      row[34] = "150ft"                 # High Elevation ← IGNORAR
      row[35] = "50ft"                  # Lowest Elevation ← IGNORAR
      row[36] = "100ft"                 # Elevation Diff ← IGNORAR

      # Post-elevación (shifted +3)
      row[37] = "Rectangular"           # LOT_SHAPE (was 34)
      row[39] = "28.0394, -81.9498"     # COORDINATES_RAW (was 36)
      row[40] = "no"                    # WETLANDS_RAW (was 37)
      row[41] = "No flood risk"         # FEMA_NOTES (was 38)
      row[42] = "https://fema.gov/test" # FEMA_URL (was 39)
      row[43] = "Zone X"                # FEMA_RISK_LEVEL (was 40)
      row[44] = "https://img.test/p.jpg" # PROPERTY_IMAGE_URL (was 41)
      row[46] = "no"                    # HOA (was 43)
      row[71] = "$175,000"              # ESTIMATED_SALE_VALUE (was 68)
      row[79] = "https://clerk.test"    # CLERK_URL (was 76)
      row[80] = "https://tax.test"      # TAX_COLLECTOR_URL (was 77)

      processor = SheetRowProcessor.new(row)

      # Verificar que col() lee las posiciones correctas
      assert_eq processor.send(:col, SheetColumnMap::STATE),         "FL",           "col(STATE)"
      assert_eq processor.send(:col, SheetColumnMap::LOT_SHAPE),     "Rectangular",  "col(LOT_SHAPE) = pos 37"
      assert_eq processor.send(:col, SheetColumnMap::WETLANDS_RAW),  "no",           "col(WETLANDS) = pos 40"
      assert_eq processor.send(:col, SheetColumnMap::FEMA_RISK_LEVEL), "Zone X",     "col(FEMA_RISK) = pos 43"
      assert_eq processor.send(:col, SheetColumnMap::HOA),           "no",           "col(HOA) = pos 46"
      assert_eq processor.send(:col, SheetColumnMap::ESTIMATED_SALE_VALUE), "$175,000", "col(EST_SALE) = pos 71"
      assert_eq processor.send(:col, SheetColumnMap::CLERK_URL),     "https://clerk.test", "col(CLERK_URL) = pos 79"
      assert_eq processor.send(:col, SheetColumnMap::TAX_COLLECTOR_URL), "https://tax.test", "col(TAX_URL) = pos 80"
    end

    # ════════════════════════════════════════════════════════════════════════
    # QA 5: Datos de elevación NO se persisten en BD
    # ════════════════════════════════════════════════════════════════════════
    def qa_5_elevation_not_persisted
      puts "\n┌────────────────────────────────────────────────────────────┐"
      puts "│  QA 5: Elevación NO contamina la BD                      │"
      puts "└────────────────────────────────────────────────────────────┘"

      # Verificar que SheetRowProcessor NO referencia posiciones 34-36
      source = File.read(Rails.root.join("app/services/sheet_row_processor.rb"))

      # Ningún campo del attrs hash debe usar las posiciones de elevación
      [34, 35, 36].each do |pos|
        # Buscar si alguna constante apunta a estas posiciones
        mapped_const = SheetColumnMap.constants.find { |c|
          SheetColumnMap.const_get(c) == pos && c.is_a?(Symbol)
        }
        if mapped_const && source.include?("col(#{mapped_const})")
          self.total += 1; self.failed += 1
          failures << "[FAIL] Processor usa col(#{mapped_const}) en pos #{pos}"
          puts "    #{FAIL} Processor referencia pos #{pos} via #{mapped_const}"
        else
          self.total += 1; self.passed += 1
          puts "    #{PASS} Pos #{pos} (elevación) no usada en Processor"
        end
      end
    end

    # ════════════════════════════════════════════════════════════════════════
    # QA 6: Rangos del Importer cubren todas las columnas
    # ════════════════════════════════════════════════════════════════════════
    def qa_6_importer_range_coverage
      puts "\n┌────────────────────────────────────────────────────────────┐"
      puts "│  QA 6: Rangos del Importer cubren columnas extendidas    │"
      puts "└────────────────────────────────────────────────────────────┘"

      # CE = columna 83 (0-based 82). Máximo índice usado = 82 (pos CE)
      max_index = SheetColumnMap.constants
        .select { |c| SheetColumnMap.const_get(c).is_a?(Integer) }
        .map { |c| SheetColumnMap.const_get(c) }
        .max

      # El rango debe cubrir hasta al menos max_index
      # CE en Excel = columna 83 (1-based) = índice 82 (0-based)
      ce_index = 82  # CE = C(3)*26 + E(5) - 1 = 82

      assert_true ce_index >= max_index, "CE (#{ce_index}) >= max_index (#{max_index})"
      assert_true GoogleSheetsImporter::DATA_RANGE.include?("CE"), "DATA_RANGE incluye CE"
      assert_true GoogleSheetsImporter::HEADER_RANGE.include?("CE"), "HEADER_RANGE incluye CE"

      # Verificar chunk range en source
      source = File.read(Rails.root.join("app/services/google_sheets_importer.rb"))
      assert_true source.match?(/CE\#\{end_row\}/) || source.include?(":CE"),
                  "Chunk range usa CE"
    end

    # ════════════════════════════════════════════════════════════════════════
    # QA 7: Arrays IGNORED son consistentes
    # ════════════════════════════════════════════════════════════════════════
    def qa_7_ignored_arrays_consistent
      puts "\n┌────────────────────────────────────────────────────────────┐"
      puts "│  QA 7: Arrays IGNORED_* son consistentes                 │"
      puts "└────────────────────────────────────────────────────────────┘"

      internal = SheetColumnMap::IGNORED_INTERNAL
      zillow   = SheetColumnMap::IGNORED_ZILLOW
      calcs    = SheetColumnMap::IGNORED_CALCS

      # Sin overlap entre arrays
      overlap_iz = internal & zillow
      overlap_ic = internal & calcs
      overlap_zc = zillow & calcs
      assert_eq overlap_iz, [], "Sin overlap INTERNAL/ZILLOW"
      assert_eq overlap_ic, [], "Sin overlap INTERNAL/CALCS"
      assert_eq overlap_zc, [], "Sin overlap ZILLOW/CALCS"

      # Elevación en INTERNAL
      assert_true internal.include?(34), "34 en IGNORED_INTERNAL"
      assert_true internal.include?(35), "35 en IGNORED_INTERNAL"
      assert_true internal.include?(36), "36 en IGNORED_INTERNAL"

      # Zillow rango shifted: 47-70
      assert_eq zillow.first, 47, "ZILLOW empieza en 47"
      assert_eq zillow.last,  70, "ZILLOW termina en 70"

      # Calcs rango shifted: 72-78
      assert_eq calcs.first, 72, "CALCS empieza en 72"
      assert_eq calcs.last,  78, "CALCS termina en 78"
    end

    # ════════════════════════════════════════════════════════════════════════
    # QA 8: Pipeline E2E — Fila con elevación → BD correcta
    # ════════════════════════════════════════════════════════════════════════
    def qa_8_full_pipeline_e2e
      puts "\n┌────────────────────────────────────────────────────────────┐"
      puts "│  QA 8: E2E Pipeline — Fila con elevación → BD            │"
      puts "└────────────────────────────────────────────────────────────┘"

      ActiveRecord::Base.transaction do
        row = Array.new(83, nil)
        row[0]  = "FL";  row[1] = "QA-County"; row[3] = "SHIFT-E2E-001"
        row[7]  = "07/01/2026"; row[8] = "$300,000"; row[9] = "$100,000"
        row[10] = "$250,000";   row[11] = "10.0"
        row[22] = "789 QA Blvd"; row[23] = "33901"; row[24] = "Fort Myers"
        row[28] = "https://regrid.test/qa"
        row[30] = "https://maps.google.com/?q=26.6,-81.8"
        row[31] = "yes"; row[32] = "yes"; row[33] = "no"

        # Elevación (DEBE ser ignorada)
        row[34] = "200"; row[35] = "80"; row[36] = "120"

        # Post-shift
        row[37] = "Irregular"
        row[39] = "26.640628, -81.872307"
        row[40] = "yes"; row[43] = "Zone AE"
        row[46] = "yes"; row[71] = "$250,000"
        row[79] = "https://clerk.qa"; row[80] = "https://tax.qa"

        result = SheetRowProcessor.process(row)
        assert_eq result, :added, "Pipeline: fila procesada"

        p = Parcel.find_by!(state: "FL", county: "QA-County", parcel_id: "SHIFT-E2E-001")

        # Campos pre-elevación intactos
        assert_eq p.market_value,   BigDecimal("300000"), "market_value"
        assert_eq p.opening_bid,    BigDecimal("100000"), "opening_bid"
        assert_present p.electric,                         "electric presente"
        assert_present p.sewer,                            "sewer presente"

        # Campos post-shift correctos
        assert_eq p.lot_shape,           "Irregular",      "lot_shape (pos 37)"
        assert_eq p.latitude,            BigDecimal("26.640628"),  "latitude (pos 39)"
        assert_eq p.longitude,           BigDecimal("-81.872307"), "longitude (pos 39)"
        assert_eq p.wetlands,            true,              "wetlands (pos 40)"
        assert_eq p.fema_risk_level,     "Zone AE",         "fema_risk_level (pos 43)"
        assert_present p.hoa,                                "hoa (pos 46) presente"
        assert_eq p.estimated_sale_value, BigDecimal("250000"), "est_sale (pos 71)"
        assert_eq p.clerk_url,           "https://clerk.qa",    "clerk_url (pos 79)"
        assert_eq p.tax_collector_url,   "https://tax.qa",      "tax_url (pos 80)"

        # Elevación NO llegó a ningún campo
        # Si pos 34 se mapeara incorrectamente a lot_shape (vieja pos),
        # lot_shape sería "200" en vez de "Irregular"
        assert_true p.lot_shape != "200",  "Elevación NO contaminó lot_shape"
        assert_true p.lot_shape != "80",   "Elevación NO contaminó lot_shape (2)"
        assert_true p.lot_shape != "120",  "Elevación NO contaminó lot_shape (3)"

        # Price per acre calculado: 100000 / 10.0 = 10000
        assert_eq p.price_per_acre, BigDecimal("10000"), "price_per_acre calculado"

        raise ActiveRecord::Rollback
      end
    end

    private

    def print_summary
      puts "\n#{SEP}"
      puts "  📋 RESUMEN QA — SHIFT +3 ELEVACIÓN"
      puts SEP
      puts "  Total: #{total} | #{PASS.gsub(/\s.*/, '')} #{passed} | #{FAIL.gsub(/\s.*/, '')} #{failed}"

      if failures.any?
        puts "\n  ── FALLOS ──"
        failures.each { |f| puts "  #{f}" }
      end

      pct = total > 0 ? (passed.to_f / total * 100).round(1) : 0
      puts "\n  ── VEREDICTO: #{pct}%"
      if failed == 0
        puts "  🏆 SHIFT +3 VALIDADO — Mapeo posicional íntegro"
      else
        puts "  🚨 HAY ERRORES — Revisar los fallos arriba"
      end
      puts SEP
    end
  end
end

ColumnShiftQA.run_all
