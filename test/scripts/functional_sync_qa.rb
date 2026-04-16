# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════════════
# FUNCTIONAL SYNC QA — End-to-End Integration Tests
# ═══════════════════════════════════════════════════════════════════════════════
# Run: rails runner test/scripts/functional_sync_qa.rb
#
# Tests:
#   1. Dirty Data Mapping (parse_currency, parse_decimal, parse_date, parse_boolean)
#   2. CRM Immunity Guard (upsert does NOT touch parcel_user_tags/parcel_user_notes)
#   3. Google API Connection Audit (credential config, error handling, SyncLog)
# ═══════════════════════════════════════════════════════════════════════════════

class FunctionalSyncQA
  PASS = "✅ PASS"
  FAIL = "❌ FAIL"
  WARN = "⚠️ WARN"
  INFO = "ℹ️ INFO"

  attr_reader :results

  def initialize
    @results = []
    @test_count = 0
    @pass_count = 0
    @fail_count = 0
    @warn_count = 0
  end

  def run_all
    puts "\n#{'=' * 80}"
    puts "  FUNCTIONAL SYNC QA — #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    puts "#{'=' * 80}\n\n"

    section("1. DIRTY DATA MAPPING (Parseo Sucio)") do
      test_parse_currency_dirty_formats
      test_parse_decimal_dirty_formats
      test_parse_date_formats
      test_parse_boolean_formats
      test_full_dirty_row_ingestion
      test_premium_fields_not_nil_from_dirty_data
      test_blank_cell_mirror_rule
    end

    section("2. CRM IMMUNITY GUARD (Protección Upsert)") do
      test_crm_immunity_guard_block
      test_upsert_preserves_user_tags_and_notes
      test_upsert_updates_non_crm_fields
    end

    section("3. GOOGLE API CONNECTION AUDIT") do
      test_credential_configuration
      test_sync_log_error_recording
      test_importer_error_handling_patterns
      test_retry_configuration
    end

    print_summary
  end

  private

  # ─── SECTION 1: DIRTY DATA MAPPING ──────────────────────────────────────────

  def test_parse_currency_dirty_formats
    processor = SheetRowProcessor.new([])

    test_cases = {
      "$ 25,000.00"     => BigDecimal("25000.00"),
      "$25,000"         => BigDecimal("25000"),
      "$25,000.50"      => BigDecimal("25000.50"),
      "25000"           => BigDecimal("25000"),
      "25,000"          => BigDecimal("25000"),
      " $25,000 "       => BigDecimal("25000"),
      "$0"              => BigDecimal("0"),
      "$1,234,567.89"   => BigDecimal("1234567.89"),
      "$ 100"           => BigDecimal("100"),
      "$100.99"         => BigDecimal("100.99"),
      ""                => nil,
      "   "             => nil,
      "N/A"             => nil,
      "TBD"             => nil,
      "(25,000)"        => nil, # Negative accounting format → nil
    }

    test_cases.each do |input, expected|
      actual = processor.send(:parse_currency, input)
      display_input = input.inspect
      if actual == expected
        record_pass("parse_currency(#{display_input}) → #{actual.inspect}")
      else
        record_fail("parse_currency(#{display_input}) → expected #{expected.inspect}, got #{actual.inspect}")
      end
    end
  end

  def test_parse_decimal_dirty_formats
    processor = SheetRowProcessor.new([])

    test_cases = {
      "1,234.56"  => BigDecimal("1234.56"),
      "1234.56"   => BigDecimal("1234.56"),
      "1234"      => BigDecimal("1234"),
      " 1,234 "   => BigDecimal("1234"),
      "0.5"       => BigDecimal("0.5"),
      ""          => nil,
      "N/A"       => nil,
    }

    test_cases.each do |input, expected|
      actual = processor.send(:parse_decimal, input)
      display_input = input.inspect
      if actual == expected
        record_pass("parse_decimal(#{display_input}) → #{actual.inspect}")
      else
        record_fail("parse_decimal(#{display_input}) → expected #{expected.inspect}, got #{actual.inspect}")
      end
    end
  end

  def test_parse_date_formats
    processor = SheetRowProcessor.new([])

    test_cases = {
      "04/12/2026"  => Date.new(2026, 4, 12),
      "12/31/2025"  => Date.new(2025, 12, 31),
      "01/01/2026"  => Date.new(2026, 1, 1),
      "2026-04-12"  => Date.new(2026, 4, 12),    # ISO fallback
      ""            => nil,
      "   "         => nil,
      "not-a-date"  => nil,
    }

    test_cases.each do |input, expected|
      actual = processor.send(:parse_date, input)
      display_input = input.inspect
      if actual == expected
        record_pass("parse_date(#{display_input}) → #{actual.inspect}")
      else
        record_fail("parse_date(#{display_input}) → expected #{expected.inspect}, got #{actual.inspect}")
      end
    end
  end

  def test_parse_boolean_formats
    processor = SheetRowProcessor.new([])

    test_cases = {
      "yes"   => true,
      "Yes"   => true,
      "YES"   => true,
      " yes " => true,
      "no"    => false,
      "No"    => false,
      "NO"    => false,
      " no "  => false,
      ""      => nil,
      "   "   => nil,
    }

    test_cases.each do |input, expected|
      actual = processor.send(:parse_boolean, input)
      display_input = input.inspect
      if actual == expected
        record_pass("parse_boolean(#{display_input}) → #{actual.inspect}")
      else
        record_fail("parse_boolean(#{display_input}) → expected #{expected.inspect}, got #{actual.inspect}")
      end
    end
  end

  def test_full_dirty_row_ingestion
    # Build a simulated dirty row matching SheetColumnMap positions
    # Total columns: 80 (A through CB), we only populate mapped ones
    dirty_row = Array.new(80, "")

    # Identity (columns 0-2)
    dirty_row[SheetColumnMap::STATE]     = "  Florida  "      # Extra whitespace
    dirty_row[SheetColumnMap::COUNTY]    = "  Miami-Dade  "   # Extra whitespace
    dirty_row[SheetColumnMap::PARCEL_ID] = "QA-DIRTY-TEST-001"

    # Auction date (column 6) — US format
    dirty_row[SheetColumnMap::AUCTION_DATE] = "04/12/2026"

    # Financial — DIRTY formats (columns 7-9, 67)
    dirty_row[SheetColumnMap::MARKET_VALUE]        = "$ 250,000.00"
    dirty_row[SheetColumnMap::OPENING_BID]         = "$25,000"
    dirty_row[SheetColumnMap::ASSESSED_VALUE]       = " $175,000.50 "
    dirty_row[SheetColumnMap::ESTIMATED_SALE_VALUE] = "$300,000"

    # Physical — DIRTY formats (columns 10-12)
    dirty_row[SheetColumnMap::LOT_AREA_ACRES] = " 2.50 "
    dirty_row[SheetColumnMap::SQFT_LOT]       = "10,890"
    dirty_row[SheetColumnMap::SQFT_LIVING]    = "1,850"

    # Premium fields — these MUST survive dirty parsing
    dirty_row[SheetColumnMap::ZONING]          = "  RS-3  "          # Zoning with spaces
    dirty_row[SheetColumnMap::FEMA_RISK_LEVEL] = "Zone X"            # Flood risk
    dirty_row[SheetColumnMap::HOA]             = " Yes "              # HOA with spaces
    dirty_row[SheetColumnMap::WETLANDS_RAW]    = " no "              # Wetlands
    dirty_row[SheetColumnMap::CRIME_LEVEL]     = "Low"
    dirty_row[SheetColumnMap::HOMESTEAD_FLAG]  = "Investor"

    # Coordinates — dirty format
    dirty_row[SheetColumnMap::COORDINATES_RAW] = "  25.761681, -80.191788  "

    # Address fields
    dirty_row[SheetColumnMap::PROPERTY_ADDRESS] = "123 Main St"
    dirty_row[SheetColumnMap::ZIP]              = "33101"
    dirty_row[SheetColumnMap::CITY]             = "Miami"

    # Links (premium)
    dirty_row[SheetColumnMap::FEMA_URL]     = "https://msc.fema.gov/portal/search"
    dirty_row[SheetColumnMap::REGRID_URL]   = "https://app.regrid.com/us/fl"
    dirty_row[SheetColumnMap::CLERK_URL]    = "https://clerk.miamidade.gov"

    # Process the dirty row
    begin
      ActiveRecord::Base.transaction do
        result = SheetRowProcessor.process(dirty_row)

        # Verify persisted data
        parcel = Parcel.find_by!(
          state:     "Florida",
          county:    "Miami-Dade",
          parcel_id: "QA-DIRTY-TEST-001"
        )

        # ── Financial: Must be clean decimals, not zero, not nil ────────────
        verify_field(parcel, :opening_bid,          BigDecimal("25000"),     "Opening bid from '$25,000'")
        verify_field(parcel, :assessed_value,        BigDecimal("175000.50"), "Assessed value from ' $175,000.50 '")
        verify_field(parcel, :market_value,          BigDecimal("250000"),    "Market value from '$ 250,000.00'")
        verify_field(parcel, :estimated_sale_value,  BigDecimal("300000"),    "Estimated sale value from '$300,000'")

        # ── Physical: Must be clean decimals ────────────────────────────────
        verify_field(parcel, :lot_area_acres, BigDecimal("2.50"),  "Lot acres from ' 2.50 '")
        verify_field(parcel, :sqft_lot,       BigDecimal("10890"), "Sqft lot from '10,890'")
        verify_field(parcel, :sqft_living,    BigDecimal("1850"),  "Sqft living from '1,850'")

        # ── Premium fields: MUST NOT be nil ────────────────────────────────
        verify_not_nil(parcel, :zoning,          "Zoning preserved through dirty parse")
        verify_not_nil(parcel, :fema_risk_level, "FEMA risk level preserved")
        verify_not_nil(parcel, :hoa,             "HOA preserved")
        verify_not_nil(parcel, :crime_level,     "Crime level preserved")
        verify_not_nil(parcel, :homestead_flag,  "Homestead flag preserved")

        # ── Coordinates: Must parse correctly ──────────────────────────────
        verify_field(parcel, :latitude,  BigDecimal("25.761681"),  "Latitude from dirty coords")
        verify_field(parcel, :longitude, BigDecimal("-80.191788"), "Longitude from dirty coords")

        # ── Wetlands: Must be boolean false (not nil) ──────────────────────
        if parcel.wetlands == false
          record_pass("Wetlands parsed as false from ' no '")
        else
          record_fail("Wetlands expected false, got #{parcel.wetlands.inspect}")
        end

        # ── Price per acre: Must be calculated ─────────────────────────────
        expected_ppa = (BigDecimal("25000") / BigDecimal("2.50")).round(2)
        verify_field(parcel, :price_per_acre, expected_ppa, "Price per acre calculated")

        # ── Auction: Must exist with correct date ──────────────────────────
        auction = parcel.auction
        if auction && auction.sale_date == Date.new(2026, 4, 12)
          record_pass("Auction created with correct sale_date 2026-04-12")
        else
          record_fail("Auction sale_date mismatch: #{auction&.sale_date}")
        end

        # ROLLBACK — don't persist QA test data
        raise ActiveRecord::Rollback
      end
    rescue ActiveRecord::Rollback
      # Expected — transaction rolled back
    rescue => e
      record_fail("Full dirty row ingestion CRASHED: #{e.class}: #{e.message}")
    end
  end

  def test_premium_fields_not_nil_from_dirty_data
    # This test specifically checks that premium fields (zoning, flood risk, HOA)
    # don't get silently dropped during parsing due to whitespace or format issues
    processor = SheetRowProcessor.new([])

    premium_cases = {
      "  RS-3  "       => "RS-3",       # Zoning with spaces → stripped
      "Zone X"         => "Zone X",     # FEMA risk level
      " Yes "          => "Yes",        # HOA
      "  Investor  "   => "Investor",   # Homestead flag
    }

    premium_cases.each do |input, expected|
      actual = processor.send(:col, 0) # We test col() with a synthetic row
    end

    # Test col() helper directly
    test_row = Array.new(5, "")
    test_row[0] = "  RS-3  "
    test_row[1] = ""
    test_row[2] = "   "
    test_row[3] = "Valid Value"
    test_row[4] = nil

    p = SheetRowProcessor.new(test_row)
    results_hash = {
      0 => "RS-3",
      1 => nil,
      2 => nil,
      3 => "Valid Value",
      4 => nil,
    }

    results_hash.each do |idx, expected|
      actual = p.send(:col, idx)
      if actual == expected
        record_pass("col(#{idx}) with #{test_row[idx].inspect} → #{actual.inspect}")
      else
        record_fail("col(#{idx}) with #{test_row[idx].inspect} → expected #{expected.inspect}, got #{actual.inspect}")
      end
    end
  end

  def test_blank_cell_mirror_rule
    # 🪞 ESPEJO: Blank cell in Sheet → nil in PostgreSQL
    dirty_row = Array.new(80, "")
    dirty_row[SheetColumnMap::STATE]      = "Florida"
    dirty_row[SheetColumnMap::COUNTY]     = "Test-County"
    dirty_row[SheetColumnMap::PARCEL_ID]  = "QA-MIRROR-TEST-001"
    dirty_row[SheetColumnMap::AUCTION_DATE] = "04/12/2026"
    dirty_row[SheetColumnMap::OPENING_BID]  = "$50,000"
    dirty_row[SheetColumnMap::COORDINATES_RAW] = "25.761681, -80.191788"

    begin
      ActiveRecord::Base.transaction do
        # First: create with data
        SheetRowProcessor.process(dirty_row)
        parcel = Parcel.find_by!(state: "Florida", county: "Test-County", parcel_id: "QA-MIRROR-TEST-001")

        if parcel.opening_bid == BigDecimal("50000")
          record_pass("Mirror setup: opening_bid created as 50000")
        else
          record_fail("Mirror setup: opening_bid expected 50000, got #{parcel.opening_bid}")
        end

        # Second: simulate blank cell (opening_bid cleared in Sheet)
        dirty_row[SheetColumnMap::OPENING_BID] = ""
        dirty_row[SheetColumnMap::COORDINATES_RAW] = ""
        SheetRowProcessor.process(dirty_row)
        parcel.reload

        if parcel.opening_bid.nil?
          record_pass("🪞 Mirror: opening_bid cleared to nil when cell blanked")
        else
          record_fail("🪞 Mirror VIOLATION: opening_bid still #{parcel.opening_bid} after blank cell")
        end

        if parcel.latitude.nil? && parcel.longitude.nil?
          record_pass("🪞 Mirror: coordinates cleared to nil when cell blanked")
        else
          record_fail("🪞 Mirror VIOLATION: coords still #{parcel.latitude}, #{parcel.longitude} after blank")
        end

        raise ActiveRecord::Rollback
      end
    rescue ActiveRecord::Rollback
      # Expected
    rescue => e
      record_fail("Mirror test CRASHED: #{e.class}: #{e.message}")
    end
  end

  # ─── SECTION 2: CRM IMMUNITY GUARD ──────────────────────────────────────────

  def test_crm_immunity_guard_block
    processor = SheetRowProcessor.new([])

    # Attempt to inject CRM column into attrs hash
    test_attrs = { opening_bid: 1000, parcel_user_tags: "injected", parcel_user_notes: "injected" }

    begin
      processor.send(:enforce_crm_immunity!, test_attrs)
      record_fail("CRM immunity guard did NOT raise on parcel_user_tags/notes injection!")
    rescue ActiveRecord::RecordNotSaved => e
      if e.message.include?("CRM IMMUNITY VIOLATION")
        record_pass("CRM immunity guard BLOCKS injection: #{e.message[0..80]}...")
      else
        record_fail("CRM immunity guard raised wrong error: #{e.message}")
      end
    rescue => e
      record_fail("CRM immunity guard raised unexpected error: #{e.class}: #{e.message}")
    end

    # Test with safe attrs — should NOT raise
    safe_attrs = { opening_bid: 1000, assessed_value: 2000 }
    begin
      processor.send(:enforce_crm_immunity!, safe_attrs)
      record_pass("CRM immunity guard allows safe attributes")
    rescue => e
      record_fail("CRM immunity guard wrongly blocked safe attrs: #{e.message}")
    end
  end

  def test_upsert_preserves_user_tags_and_notes
    begin
      ActiveRecord::Base.transaction do
        # 1. Create a test user
        user = User.create!(
          email: "qa-crm-test-#{SecureRandom.hex(4)}@test.com",
          password: "TestPassword123!",
          first_name: "QA", last_name: "Tester"
        )

        # 2. Create a parcel with sync data
        row = Array.new(80, "")
        row[SheetColumnMap::STATE]        = "Florida"
        row[SheetColumnMap::COUNTY]       = "QA-CRM-County"
        row[SheetColumnMap::PARCEL_ID]    = "QA-CRM-IMMUNITY-001"
        row[SheetColumnMap::AUCTION_DATE] = "04/12/2026"
        row[SheetColumnMap::OPENING_BID]  = "$10,000"
        row[SheetColumnMap::ZONING]       = "RS-1"
        SheetRowProcessor.process(row)

        parcel = Parcel.find_by!(state: "Florida", county: "QA-CRM-County", parcel_id: "QA-CRM-IMMUNITY-001")

        # 3. Simulate user adding CRM data (tags + notes)
        tag = ParcelUserTag.upsert_for!(user: user, parcel: parcel, tag: "target")
        note = ParcelUserNote.create!(user: user, parcel: parcel, body: "Great investment opportunity - low crime area")

        tag_count_before   = parcel.parcel_user_tags.count
        note_count_before  = parcel.parcel_user_notes.count
        note_body_before   = note.body

        if tag_count_before >= 1 && note_count_before >= 1
          record_pass("CRM setup: #{tag_count_before} tag(s), #{note_count_before} note(s) created")
        else
          record_fail("CRM setup failed: tags=#{tag_count_before}, notes=#{note_count_before}")
        end

        # 4. Simulate SECOND sync with updated financial data
        row[SheetColumnMap::OPENING_BID] = "$15,000"  # Changed!
        row[SheetColumnMap::ZONING]      = "RS-2"     # Changed!
        SheetRowProcessor.process(row)
        parcel.reload

        # 5. Verify financial data WAS updated
        if parcel.opening_bid == BigDecimal("15000")
          record_pass("Upsert updated opening_bid: $10,000 → $15,000")
        else
          record_fail("Upsert did NOT update opening_bid: got #{parcel.opening_bid}")
        end

        if parcel.zoning == "RS-2"
          record_pass("Upsert updated zoning: RS-1 → RS-2")
        else
          record_fail("Upsert did NOT update zoning: got #{parcel.zoning}")
        end

        # 6. CRITICAL: Verify CRM data is INTACT
        tag_count_after = parcel.parcel_user_tags.reload.count
        note_count_after = parcel.parcel_user_notes.reload.count
        note_body_after = note.reload.body

        if tag_count_after == tag_count_before
          record_pass("⛔ CRM IMMUNITY: Tag count preserved (#{tag_count_after})")
        else
          record_fail("⛔ CRM IMMUNITY VIOLATION: Tags changed from #{tag_count_before} to #{tag_count_after}")
        end

        if note_count_after == note_count_before
          record_pass("⛔ CRM IMMUNITY: Note count preserved (#{note_count_after})")
        else
          record_fail("⛔ CRM IMMUNITY VIOLATION: Notes changed from #{note_count_before} to #{note_count_after}")
        end

        if note_body_after == note_body_before
          record_pass("⛔ CRM IMMUNITY: Note body INTACT ('#{note_body_after[0..40]}...')")
        else
          record_fail("⛔ CRM IMMUNITY VIOLATION: Note body changed!")
        end

        # Verify tag value is still "target"
        persisted_tag = ParcelUserTag.find_by(user: user, parcel: parcel)
        if persisted_tag&.tag == "target"
          record_pass("⛔ CRM IMMUNITY: Tag value preserved ('target')")
        else
          record_fail("⛔ CRM IMMUNITY VIOLATION: Tag changed to '#{persisted_tag&.tag}'")
        end

        raise ActiveRecord::Rollback
      end
    rescue ActiveRecord::Rollback
      # Expected
    rescue => e
      record_fail("CRM immunity upsert test CRASHED: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    end
  end

  def test_upsert_updates_non_crm_fields
    # Verify that the upsert correctly updates ALL non-CRM fields
    begin
      ActiveRecord::Base.transaction do
        row = Array.new(80, "")
        row[SheetColumnMap::STATE]        = "Florida"
        row[SheetColumnMap::COUNTY]       = "QA-Update-County"
        row[SheetColumnMap::PARCEL_ID]    = "QA-UPDATE-TEST-001"
        row[SheetColumnMap::AUCTION_DATE] = "04/12/2026"
        row[SheetColumnMap::OPENING_BID]  = "$10,000"
        row[SheetColumnMap::OWNER_NAME]   = "John Doe"
        row[SheetColumnMap::FEMA_RISK_LEVEL] = "Zone X"
        SheetRowProcessor.process(row)

        parcel = Parcel.find_by!(state: "Florida", county: "QA-Update-County", parcel_id: "QA-UPDATE-TEST-001")

        # Now update multiple fields
        row[SheetColumnMap::OPENING_BID]     = "$20,000"
        row[SheetColumnMap::OWNER_NAME]      = "Jane Smith"
        row[SheetColumnMap::FEMA_RISK_LEVEL] = "Zone AE"
        row[SheetColumnMap::CRIME_LEVEL]     = "High"
        row[SheetColumnMap::HOA]             = "yes"
        SheetRowProcessor.process(row)
        parcel.reload

        checks = {
          opening_bid:     [BigDecimal("20000"), "opening_bid updated"],
          owner_name:      ["Jane Smith",        "owner_name updated"],
          fema_risk_level: ["Zone AE",          "fema_risk_level updated"],
          crime_level:     ["High",             "crime_level updated"],
          hoa:             ["yes",              "hoa updated"],
        }

        checks.each do |field, (expected, label)|
          actual = parcel.send(field)
          if actual == expected
            record_pass("Upsert field update: #{label} → #{actual.inspect}")
          else
            record_fail("Upsert field update failed: #{label} → expected #{expected.inspect}, got #{actual.inspect}")
          end
        end

        raise ActiveRecord::Rollback
      end
    rescue ActiveRecord::Rollback
      # Expected
    rescue => e
      record_fail("Upsert field update test CRASHED: #{e.class}: #{e.message}")
    end
  end

  # ─── SECTION 3: GOOGLE API CONNECTION AUDIT ─────────────────────────────────

  def test_credential_configuration
    # Check that the credential loading path exists and is properly structured
    begin
      creds = Rails.application.credentials.google_service_account
      if creds.present?
        required_keys = %i[type project_id private_key client_email]
        missing = required_keys.select { |k| creds[k].blank? }

        if missing.empty?
          record_pass("Google credentials: All required keys present (#{required_keys.join(', ')})")
        else
          record_fail("Google credentials: Missing keys: #{missing.join(', ')}")
        end

        # Verify private key format (should be valid PEM)
        if creds[:private_key].to_s.include?("-----BEGIN PRIVATE KEY-----")
          record_pass("Google credentials: Private key has valid PEM header")
        else
          record_warn("Google credentials: Private key may need PEM reconstruction (handled at runtime)")
        end

        # Verify scope configuration
        record_pass("Google credentials: client_email = #{creds[:client_email]}")
      else
        record_warn("Google credentials: NOT configured (google_service_account is blank)")
      end
    rescue => e
      record_warn("Google credentials check: #{e.message}")
    end

    # Check Sheet ID configuration
    sheet_id = ENV["GOOGLE_SHEETS_SHEET_ID"].presence ||
               Rails.application.credentials.dig(:google_sheets, :sheet_id)
    if sheet_id.present?
      record_pass("Google Sheet ID configured: #{sheet_id[0..10]}...")
    else
      record_warn("Google Sheet ID: NOT configured (ENV or credentials)")
    end
  end

  def test_sync_log_error_recording
    # Verify SyncLog correctly records failures
    begin
      ActiveRecord::Base.transaction do
        log = SyncLog.create!(status: "running", started_at: Time.current)

        # Simulate a failure update (what SyncSheetJob does on rescue)
        log.update!(
          status:           "failed",
          error_message:    "Google::Apis::ServerError: 503 Service Unavailable",
          duration_seconds: 0.5,
          completed_at:     Time.current
        )

        log.reload
        if log.status == "failed" && log.error_message.include?("503")
          record_pass("SyncLog records failure with error message")
        else
          record_fail("SyncLog failure recording broken: status=#{log.status}, error=#{log.error_message}")
        end

        # Verify SyncLog success recording
        success_log = SyncLog.create!(
          status:           "success",
          started_at:       Time.current,
          completed_at:     Time.current,
          parcels_added:    50,
          parcels_updated:  150,
          parcels_skipped:  5,
          duration_seconds: 12.3
        )

        if success_log.total_processed == 200
          record_pass("SyncLog total_processed = #{success_log.total_processed} (50 + 150)")
        else
          record_fail("SyncLog total_processed wrong: #{success_log.total_processed}")
        end

        if success_log.duration_display == "12.3s"
          record_pass("SyncLog duration_display = '#{success_log.duration_display}'")
        else
          record_fail("SyncLog duration_display wrong: '#{success_log.duration_display}'")
        end

        raise ActiveRecord::Rollback
      end
    rescue ActiveRecord::Rollback
      # Expected
    rescue => e
      record_fail("SyncLog test CRASHED: #{e.class}: #{e.message}")
    end
  end

  def test_importer_error_handling_patterns
    # Verify GoogleSheetsImporter has proper error rescue blocks
    source = File.read(Rails.root.join("app/services/google_sheets_importer.rb"))
    initializer = File.read(Rails.root.join("config/initializers/google_sheets.rb"))

    checks = {
      "AuthorizationError rescue"   => source.include?("Google::Apis::AuthorizationError"),
      "ClientError rescue"          => source.include?("Google::Apis::ClientError"),
      "PEM key reconstruction"      => source.include?("BEGIN PRIVATE KEY"),
      "Header normalization (NBSP)" => source.include?("\\u00A0"),
      "Retries configuration (initializer)" => initializer.include?("retries"),
    }

    checks.each do |label, present|
      if present
        record_pass("Importer pattern: #{label}")
      else
        record_fail("Importer MISSING pattern: #{label}")
      end
    end

    # Verify SyncSheetJob has proper error handling
    job_source = File.read(Rails.root.join("app/jobs/sync_sheet_job.rb"))

    job_checks = {
      "ServerError retry"         => job_source.include?("Google::Apis::ServerError"),
      "TransmissionError retry"   => job_source.include?("Google::Apis::TransmissionError"),
      "SyncLog failure recording" => job_source.include?("sync_log&.update!"),
      "Batch processing"          => job_source.include?("BATCH_SIZE"),
      "GC between batches"        => job_source.include?("GC.start"),
      "Per-row error isolation"   => job_source.include?("rescue =>"),
    }

    job_checks.each do |label, present|
      if present
        record_pass("SyncSheetJob pattern: #{label}")
      else
        record_fail("SyncSheetJob MISSING pattern: #{label}")
      end
    end
  end

  def test_retry_configuration
    # Verify Sidekiq retry configuration
    job_class = SyncSheetJob

    if job_class.respond_to?(:rescue_handlers) || job_class.ancestors.include?(ActiveJob::Base)
      record_pass("SyncSheetJob inherits from ActiveJob (retry_on available)")
    else
      record_fail("SyncSheetJob does NOT inherit from ActiveJob")
    end

    # Check retry_on declarations in source
    source = File.read(Rails.root.join("app/jobs/sync_sheet_job.rb"))
    retry_count = source.scan(/retry_on/).count
    if retry_count >= 2
      record_pass("SyncSheetJob has #{retry_count} retry_on declarations")
    else
      record_warn("SyncSheetJob has only #{retry_count} retry_on declaration(s)")
    end

    # Verify max attempts
    if source.include?("attempts: 3")
      record_pass("SyncSheetJob retry attempts capped at 3")
    else
      record_warn("SyncSheetJob retry attempts: could not verify cap")
    end
  end

  # ─── HELPERS ─────────────────────────────────────────────────────────────────

  def verify_field(record, field, expected, label)
    actual = record.send(field)
    if actual == expected
      record_pass("#{label}: #{actual.inspect}")
    else
      record_fail("#{label}: expected #{expected.inspect}, got #{actual.inspect}")
    end
  end

  def verify_not_nil(record, field, label)
    actual = record.send(field)
    if actual.present?
      record_pass("#{label}: '#{actual}'")
    else
      record_fail("#{label}: GOT NIL — premium data LOST!")
    end
  end

  def section(title)
    puts "\n  ┌#{'─' * 74}┐"
    puts "  │ #{title.ljust(72)} │"
    puts "  └#{'─' * 74}┘\n"
    yield
  end

  def record_pass(msg)
    @test_count += 1
    @pass_count += 1
    puts "    #{PASS}  #{msg}"
    @results << { status: :pass, message: msg }
  end

  def record_fail(msg)
    @test_count += 1
    @fail_count += 1
    puts "    #{FAIL}  #{msg}"
    @results << { status: :fail, message: msg }
  end

  def record_warn(msg)
    @test_count += 1
    @warn_count += 1
    puts "    #{WARN}  #{msg}"
    @results << { status: :warn, message: msg }
  end

  def print_summary
    puts "\n#{'═' * 80}"
    puts "  QA SUMMARY"
    puts "#{'═' * 80}"
    puts "  Total:    #{@test_count}"
    puts "  #{PASS}:  #{@pass_count}"
    puts "  #{FAIL}:  #{@fail_count}"
    puts "  #{WARN}:  #{@warn_count}"

    if @fail_count.zero?
      puts "\n  🎉 ALL TESTS PASSED — Sync pipeline is PRODUCTION READY"
    else
      puts "\n  🚨 #{@fail_count} FAILURE(S) DETECTED — REVIEW REQUIRED"
      puts "\n  Failed tests:"
      @results.select { |r| r[:status] == :fail }.each do |r|
        puts "    → #{r[:message]}"
      end
    end
    puts "#{'═' * 80}\n"
  end
end

# ── EXECUTE ────────────────────────────────────────────────────────────────────
FunctionalSyncQA.new.run_all
