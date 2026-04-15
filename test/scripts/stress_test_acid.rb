# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════════════
# STRESS TEST ÁCIDO — Auditoría de Integridad de Datos (v2)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Ejecutar con:  rails runner test/scripts/stress_test_acid.rb
#
# v2: Cada sub-prueba usa SAVEPOINT independiente para evitar que un error
#     de PostgreSQL (PG::InFailedSqlTransaction) contamine las pruebas
#     subsiguientes dentro de la misma transacción.
#

module StressTestAcid
  SEPARATOR = "═" * 78
  PASS = "✅ PASS"
  FAIL = "❌ FAIL"

  class << self
    def run_all
      puts "\n#{SEPARATOR}"
      puts "  🔬 STRESS TEST ÁCIDO v2 — Auditoría Extrema de Integridad"
      puts "  #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}"
      puts SEPARATOR

      results = {}
      results[:prueba_1] = prueba_1_unique_violation
      results[:prueba_2] = prueba_2_null_handling
      results[:prueba_3] = prueba_3_upsert_crm_immunity

      print_summary(results)
      results
    end

    # Helper: ejecuta un bloque dentro de un SAVEPOINT aislado.
    # Si el bloque arroja una excepción, el SAVEPOINT se revierte
    # pero la transacción padre sigue viva para las siguientes pruebas.
    def isolated_test(label)
      ActiveRecord::Base.connection.execute("SAVEPOINT stress_#{label}")
      begin
        result = yield
        ActiveRecord::Base.connection.execute("RELEASE SAVEPOINT stress_#{label}")
        result
      rescue => e
        ActiveRecord::Base.connection.execute("ROLLBACK TO SAVEPOINT stress_#{label}")
        raise e
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PRUEBA 1: Violación de Restricción Única (Database Layer)
    # ═══════════════════════════════════════════════════════════════════════════

    def prueba_1_unique_violation
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 1: Violación de Restricción Única (DB Layer)      │"
      puts "└─────────────────────────────────────────────────────────────┘"

      sub_results = {}

      ActiveRecord::Base.transaction do
        # Setup: crear parcela semilla en su propio savepoint
        seed = nil
        isolated_test("1_setup") do
          seed = Parcel.create!(
            state: "__TEST_STATE__",
            county: "__TEST_COUNTY__",
            parcel_id: "__TEST_PID_001__",
            address: "123 Test St",
            data_source: "stress_test"
          )
        end
        puts "  📌 Parcela semilla creada: id=#{seed.id} (#{seed.state}/#{seed.county}/#{seed.parcel_id})"

        # ── Vector 1A: save(validate: false) ────────────────────────────────
        print "  [1A] save(validate: false)... "
        begin
          isolated_test("1a") do
            dup = Parcel.new(
              state: "__TEST_STATE__",
              county: "__TEST_COUNTY__",
              parcel_id: "__TEST_PID_001__",
              address: "456 Dup Ave"
            )
            dup.save(validate: false)
            raise "UNEXPECTED: Duplicado insertado sin error"
          end
          puts "#{FAIL} — Duplicado insertado sin error (!)"
          sub_results["1A"] = :fail
        rescue ActiveRecord::RecordNotUnique => e
          puts "#{PASS} — PG::UniqueViolation capturada"
          puts "         Index: idx_parcels_unique_state_county_pid"
          sub_results["1A"] = :pass
        rescue RuntimeError => e
          puts "#{FAIL} — #{e.message}"
          sub_results["1A"] = :fail
        rescue => e
          puts "#{FAIL} — #{e.class}: #{e.message.truncate(100)}"
          sub_results["1A"] = :fail
        end

        # ── Vector 1B: SQL INSERT directo ────────────────────────────────────
        print "  [1B] INSERT directo con SQL raw... "
        begin
          isolated_test("1b") do
            ActiveRecord::Base.connection.execute(<<~SQL)
              INSERT INTO parcels (state, county, parcel_id, address, created_at, updated_at)
              VALUES ('__TEST_STATE__', '__TEST_COUNTY__', '__TEST_PID_001__', '789 Raw SQL Ave', NOW(), NOW())
            SQL
            raise "UNEXPECTED: Duplicado insertado vía SQL sin error"
          end
          puts "#{FAIL} — Duplicado insertado vía SQL"
          sub_results["1B"] = :fail
        rescue ActiveRecord::RecordNotUnique => e
          puts "#{PASS} — PG::UniqueViolation capturada (SQL directo)"
          sub_results["1B"] = :pass
        rescue RuntimeError => e
          puts "#{FAIL} — #{e.message}"
          sub_results["1B"] = :fail
        rescue => e
          # ActiveRecord::StatementInvalid wrapping PG::UniqueViolation
          if e.message.include?("UniqueViolation") || e.message.include?("unique constraint")
            puts "#{PASS} — PG::UniqueViolation capturada (via StatementInvalid)"
            sub_results["1B"] = :pass
          else
            puts "#{FAIL} — #{e.class}: #{e.message.truncate(100)}"
            sub_results["1B"] = :fail
          end
        end

        # ── Vector 1C: insert_all (bulk) ─────────────────────────────────────
        print "  [1C] INSERT via insert_all (bulk)... "
        begin
          isolated_test("1c") do
            # insert_all! raises on conflict (unlike insert_all which skips)
            Parcel.insert_all!([{
              state: "__TEST_STATE__",
              county: "__TEST_COUNTY__",
              parcel_id: "__TEST_PID_001__",
              address: "101 Bulk Blvd",
              created_at: Time.current,
              updated_at: Time.current
            }])
            raise "UNEXPECTED: insert_all! no arrojó error"
          end
          puts "#{FAIL} — Duplicado insertado vía insert_all!"
          sub_results["1C"] = :fail
        rescue ActiveRecord::RecordNotUnique => e
          puts "#{PASS} — PG::UniqueViolation capturada (insert_all!)"
          sub_results["1C"] = :pass
        rescue RuntimeError => e
          puts "#{FAIL} — #{e.message}"
          sub_results["1C"] = :fail
        rescue => e
          if e.message.include?("UniqueViolation") || e.message.include?("unique constraint")
            puts "#{PASS} — PG::UniqueViolation capturada"
            sub_results["1C"] = :pass
          else
            puts "#{FAIL} — #{e.class}: #{e.message.truncate(100)}"
            sub_results["1C"] = :fail
          end
        end

        raise ActiveRecord::Rollback
      end

      all_pass = sub_results.values.all? { |v| v == :pass }
      puts "  ── Resultado Prueba 1: #{all_pass ? PASS : FAIL}"
      { status: all_pass ? :pass : :fail, details: sub_results }
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PRUEBA 2: Rechazo de Basura (Null Handling)
    # ═══════════════════════════════════════════════════════════════════════════

    def prueba_2_null_handling
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 2: Rechazo de Basura (NULL Handling)              │"
      puts "└─────────────────────────────────────────────────────────────┘"

      # Inspeccionar constraints
      puts "  📊 Inspeccionando constraints de columna en PostgreSQL..."
      columns_info = ActiveRecord::Base.connection.columns("parcels")
      %w[state county parcel_id].each do |col_name|
        col = columns_info.find { |c| c.name == col_name }
        nullable = col.null != false
        puts "    #{col_name}: type=#{col.sql_type}, nullable=#{nullable}, NOT_NULL=#{!nullable}"
      end

      null_scenarios = {
        "2A" => { state: nil,              county: "__TEST_COUNTY__", parcel_id: "__TEST_PID_N1__", label: "state=NULL" },
        "2B" => { state: "__TEST_STATE__",  county: nil,              parcel_id: "__TEST_PID_N2__", label: "county=NULL" },
        "2C" => { state: "__TEST_STATE__",  county: "__TEST_COUNTY__", parcel_id: nil,               label: "parcel_id=NULL" },
        "2D" => { state: nil,              county: nil,              parcel_id: nil,               label: "ALL THREE = NULL" }
      }

      sub_results = {}

      ActiveRecord::Base.transaction do
        null_scenarios.each do |key, scenario|
          print "  [#{key}] #{scenario[:label]}... "
          begin
            isolated_test("2_#{key}") do
              ActiveRecord::Base.connection.execute(<<~SQL)
                INSERT INTO parcels (state, county, parcel_id, created_at, updated_at)
                VALUES (#{scenario[:state].nil? ? 'NULL' : "'#{scenario[:state]}'"}, 
                        #{scenario[:county].nil? ? 'NULL' : "'#{scenario[:county]}'"}, 
                        #{scenario[:parcel_id].nil? ? 'NULL' : "'#{scenario[:parcel_id]}'"}, 
                        NOW(), NOW())
              SQL
              raise "UNEXPECTED: NULL insertado sin error"
            end
            puts "#{FAIL} — NULL insertado sin error (BD NO rechaza NULLs)"
            sub_results[key] = :fail
          rescue ActiveRecord::NotNullViolation => e
            puts "#{PASS} — NotNullViolation: #{e.message.truncate(80)}"
            sub_results[key] = :pass
          rescue RuntimeError => e
            puts "#{FAIL} — #{e.message}"
            sub_results[key] = :fail
          rescue => e
            if e.message.include?("not-null") || e.message.include?("null value") || e.message.include?("NotNullViolation")
              puts "#{PASS} — NOT NULL constraint activo"
              sub_results[key] = :pass
            else
              puts "#{FAIL} — #{e.class}: #{e.message.truncate(80)}"
              sub_results[key] = :fail
            end
          end
        end

        raise ActiveRecord::Rollback
      end

      all_pass = sub_results.values.all? { |v| v == :pass }
      puts "  ── Resultado Prueba 2: #{all_pass ? PASS : FAIL}"
      { status: all_pass ? :pass : :fail, details: sub_results }
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PRUEBA 3: Prueba de Fuego — Upsert + CRM Immunity
    # ═══════════════════════════════════════════════════════════════════════════

    def prueba_3_upsert_crm_immunity
      puts "\n┌─────────────────────────────────────────────────────────────┐"
      puts "│  PRUEBA 3: Prueba de Fuego — Upsert + CRM Immunity       │"
      puts "└─────────────────────────────────────────────────────────────┘"

      sub_results = {}

      ActiveRecord::Base.transaction do
        # ── Setup ──────────────────────────────────────────────────────────
        user = User.create!(
          email: "stress_test_#{SecureRandom.hex(4)}@test.local",
          password: "TestPassword123!",
          first_name: "Stress",
          last_name: "Tester"
        )

        auction = Auction.create!(
          state: "__TEST_FL__",
          county: "__TEST_DUVAL__",
          sale_date: Date.new(2026, 5, 15),
          auction_type: "tax_deed",
          status: "upcoming"
        )

        parcel = Parcel.create!(
          auction: auction,
          state: "__TEST_FL__",
          county: "__TEST_DUVAL__",
          parcel_id: "__TEST_PID_SYNC_01__",
          address: "100 Original St",
          city: "Jacksonville",
          owner_name: "John Original",
          opening_bid: BigDecimal("5000.00"),
          assessed_value: BigDecimal("75000.00"),
          zoning: "R-1",
          data_source: "google_sheets",
          last_synced_at: 1.day.ago
        )

        tag = ParcelUserTag.create!(user: user, parcel: parcel, tag: "target")
        note = ParcelUserNote.create!(user: user, parcel: parcel, body: "This property looks promising! Great location near downtown.")

        puts "  📌 Setup completo:"
        puts "    Parcel: id=#{parcel.id} (#{parcel.state}/#{parcel.county}/#{parcel.parcel_id})"
        puts "    Opening Bid ANTES: $#{parcel.opening_bid}"
        puts "    Zoning ANTES: #{parcel.zoning}"
        puts "    Owner ANTES: #{parcel.owner_name}"
        puts "    CRM Tag: #{tag.tag} (id=#{tag.id})"
        puts "    CRM Note: \"#{note.body.truncate(50)}\" (id=#{note.id})"

        # ── Simular fila del Sheet ─────────────────────────────────────────
        puts "\n  🔄 Simulando sync de fila del Sheet..."
        simulated_row = Array.new(80, nil)
        simulated_row[SheetColumnMap::STATE]            = "__TEST_FL__"
        simulated_row[SheetColumnMap::COUNTY]           = "__TEST_DUVAL__"
        simulated_row[SheetColumnMap::PARCEL_ID]        = "__TEST_PID_SYNC_01__"
        simulated_row[SheetColumnMap::AUCTION_DATE]     = "05/15/2026"
        simulated_row[SheetColumnMap::OPENING_BID]      = "$8,500.00"
        simulated_row[SheetColumnMap::ASSESSED_VALUE]   = "$75,000.00"
        simulated_row[SheetColumnMap::MARKET_VALUE]     = "$90,000.00"
        simulated_row[SheetColumnMap::ADDRESS]          = "100 Updated St"
        simulated_row[SheetColumnMap::CITY]             = "Jacksonville Beach"
        simulated_row[SheetColumnMap::ZIP]              = "32250"
        simulated_row[SheetColumnMap::ZONING]           = ""     # BORRADO → nil
        simulated_row[SheetColumnMap::OWNER_NAME]       = ""     # BORRADO → nil

        result = SheetRowProcessor.process(simulated_row)
        parcel.reload

        # ── Verificaciones ─────────────────────────────────────────────────
        # 3A: opening_bid actualizado
        print "  [3A] Opening bid actualizado ($5,000 → $8,500)... "
        if parcel.opening_bid == BigDecimal("8500.00")
          puts "#{PASS} — opening_bid = $#{parcel.opening_bid}"
          sub_results["3A"] = :pass
        else
          puts "#{FAIL} — opening_bid = $#{parcel.opening_bid} (esperado: $8500.00)"
          sub_results["3A"] = :fail
        end

        # 3B: zoning vaciado
        print "  [3B] Zoning vaciado (Espejo Infalible)... "
        if parcel.zoning.nil?
          puts "#{PASS} — zoning = nil"
          sub_results["3B"] = :pass
        else
          puts "#{FAIL} — zoning = '#{parcel.zoning}'"
          sub_results["3B"] = :fail
        end

        # 3C: owner_name vaciado
        print "  [3C] Owner name vaciado (Espejo Infalible)... "
        if parcel.owner_name.nil?
          puts "#{PASS} — owner_name = nil"
          sub_results["3C"] = :pass
        else
          puts "#{FAIL} — owner_name = '#{parcel.owner_name}'"
          sub_results["3C"] = :fail
        end

        # 3D: retornó :updated
        print "  [3D] SheetRowProcessor retornó :updated... "
        if result == :updated
          puts "#{PASS} — result = :updated"
          sub_results["3D"] = :pass
        else
          puts "#{FAIL} — result = #{result.inspect}"
          sub_results["3D"] = :fail
        end

        # 3E: city actualizado
        print "  [3E] City actualizado... "
        if parcel.city == "Jacksonville Beach"
          puts "#{PASS} — city = '#{parcel.city}'"
          sub_results["3E"] = :pass
        else
          puts "#{FAIL} — city = '#{parcel.city}'"
          sub_results["3E"] = :fail
        end

        # 3F: CRM Tags intactas
        print "  [3F] CRM Tags intactas... "
        tags_after = ParcelUserTag.where(user: user, parcel: parcel)
        if tags_after.count == 1 && tags_after.first.tag == "target"
          puts "#{PASS} — #{tags_after.count} tag(s), tag='#{tags_after.first.tag}'"
          sub_results["3F"] = :pass
        else
          puts "#{FAIL} — Tags: #{tags_after.map(&:tag).inspect}"
          sub_results["3F"] = :fail
        end

        # 3G: CRM Notes intactas
        print "  [3G] CRM Notes intactas... "
        notes_after = ParcelUserNote.where(user: user, parcel: parcel)
        if notes_after.count == 1 && notes_after.first.body.include?("looks promising")
          puts "#{PASS} — #{notes_after.count} nota(s), body intacto"
          sub_results["3G"] = :pass
        else
          puts "#{FAIL} — Notes alteradas"
          sub_results["3G"] = :fail
        end

        # 3H: enforce_crm_immunity! ante inyección
        print "  [3H] CRM Immunity guard bloquea inyección... "
        begin
          processor = SheetRowProcessor.new(simulated_row)
          processor.send(:enforce_crm_immunity!, { parcel_user_tags: "malicious", opening_bid: 999 })
          puts "#{FAIL} — No se levantó excepción"
          sub_results["3H"] = :fail
        rescue ActiveRecord::RecordNotSaved => e
          if e.message.include?("CRM IMMUNITY VIOLATION")
            puts "#{PASS} — Guard activado correctamente"
            sub_results["3H"] = :pass
          else
            puts "#{FAIL} — Excepción incorrecta"
            sub_results["3H"] = :fail
          end
        rescue => e
          puts "#{FAIL} — #{e.class}: #{e.message.truncate(80)}"
          sub_results["3H"] = :fail
        end

        # 3I: No se creó duplicado
        print "  [3I] No se creó duplicado... "
        count = Parcel.where(state: "__TEST_FL__", county: "__TEST_DUVAL__", parcel_id: "__TEST_PID_SYNC_01__").count
        if count == 1
          puts "#{PASS} — #{count} parcela con esa clave compuesta"
          sub_results["3I"] = :pass
        else
          puts "#{FAIL} — #{count} parcelas (esperado: 1)"
          sub_results["3I"] = :fail
        end

        raise ActiveRecord::Rollback
      end

      all_pass = sub_results.values.all? { |v| v == :pass }
      puts "  ── Resultado Prueba 3: #{all_pass ? PASS : FAIL}"
      { status: all_pass ? :pass : :fail, details: sub_results }
    end

    private

    def print_summary(results)
      puts "\n#{SEPARATOR}"
      puts "  📋 RESUMEN EJECUTIVO"
      puts SEPARATOR

      results.each do |name, result|
        status = result[:status] == :pass ? PASS : FAIL
        label = name.to_s.gsub("_", " ").upcase
        puts "  #{label}: #{status}"
        result[:details].each do |sub_key, sub_status|
          icon = sub_status == :pass ? "✅" : "❌"
          puts "    [#{sub_key}] #{icon}"
        end
      end

      total_pass = results.values.all? { |r| r[:status] == :pass }
      puts "\n  ── VEREDICTO FINAL: #{total_pass ? '🏆 BASE DE DATOS BLINDADA — Duplicación es MATEMÁTICAMENTE IMPOSIBLE' : '🚨 VULNERABILIDADES DETECTADAS'}"
      puts SEPARATOR
    end
  end
end

StressTestAcid.run_all
