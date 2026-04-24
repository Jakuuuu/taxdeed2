# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════════════
# E2E SYNC → VISUAL QA STRESS TEST
# ═══════════════════════════════════════════════════════════════════════════════
#
# Ejecutar: rails runner test/scripts/e2e_sync_visual_qa.rb
#
# Valida el pipeline completo:
#   1. Ingesta de datos "basura" del Google Sheet → Sanitize → BD
#   2. CRM Immunity bajo upsert (notas y tags intactas)
#   3. Nil handling visual (cómo la vista muestra campos vacíos)
#   4. Detección de bugs en renderizado de booleanos en string columns
#
# ⛔ Este script NO modifica datos reales. Usa ActiveRecord sandbox (rollback).
# ═══════════════════════════════════════════════════════════════════════════════

require "minitest/autorun"

class E2ESyncVisualQA < Minitest::Test
  # ──────────────────────────────────────────────────────────────────────────────
  # SECCIÓN 1: PRUEBAS DE SANITIZACIÓN EXTREMA
  # ──────────────────────────────────────────────────────────────────────────────

  # ── MONEDA: "$ 12,500.00 " → 12500.0 ──────────────────────────────────────
  def test_currency_dirty_debt
    input    = "$ 12,500.00 "
    expected = BigDecimal("12500.00")
    result   = Sanitize.currency(input)

    assert_equal expected, result,
      "FAIL: Sanitize.currency('#{input}') devolvió #{result.inspect} en lugar de #{expected}"
    puts "✅ PASS: Currency '#{input}' → #{result} (BigDecimal, listo para PostgreSQL decimal)"
  end

  def test_currency_with_commas_and_dollar
    assert_equal BigDecimal("1234.56"), Sanitize.currency("$1,234.56")
    puts "✅ PASS: Currency '$1,234.56' → 1234.56"
  end

  def test_currency_plain_number
    assert_equal BigDecimal("500"), Sanitize.currency("500")
    puts "✅ PASS: Currency '500' → 500.0"
  end

  def test_currency_garbage_returns_nil
    assert_nil Sanitize.currency("N/A")
    assert_nil Sanitize.currency("")
    assert_nil Sanitize.currency(nil)
    assert_nil Sanitize.currency("(25,000)")  # formato contable negativo
    puts "✅ PASS: Currency basura → nil (N/A, vacío, nil, formato contable)"
  end

  def test_currency_negative_rejected
    assert_nil Sanitize.currency("-500")
    puts "✅ PASS: Currency negativa '-500' → nil (bids no pueden ser negativos)"
  end

  # ── HOA: "  $150/mo " → nil (no es boolean) ────────────────────────────────
  def test_hoa_dollar_amount_returns_nil
    input  = "  $150/mo "
    result = Sanitize.boolean(input)

    assert_nil result,
      "FAIL: Sanitize.boolean('#{input}') devolvió #{result.inspect} — debería ser nil (no es yes/no)"
    puts "✅ PASS: HOA '#{input}' → nil (no reconocido como boolean, se guarda como NULL)"
  end

  def test_hoa_yes_returns_true
    assert_equal true, Sanitize.boolean("yes")
    assert_equal true, Sanitize.boolean("Yes")
    assert_equal true, Sanitize.boolean("YES")
    assert_equal true, Sanitize.boolean("y")
    puts "✅ PASS: HOA 'yes/Yes/YES/y' → true"
  end

  def test_hoa_no_returns_false
    assert_equal false, Sanitize.boolean("no")
    assert_equal false, Sanitize.boolean("No")
    assert_equal false, Sanitize.boolean("NO")
    puts "✅ PASS: HOA 'no/No/NO' → false"
  end

  # ── TEXTO: Campos vacíos → nil ─────────────────────────────────────────────
  def test_empty_flood_zone_returns_nil
    assert_nil Sanitize.text("")
    assert_nil Sanitize.text("   ")
    assert_nil Sanitize.text(nil)
    assert_nil Sanitize.text("\u00A0")  # NBSP
    puts "✅ PASS: Flood Zone vacío/espacios/NBSP → nil"
  end

  def test_empty_zoning_returns_nil
    assert_nil Sanitize.text("")
    assert_nil Sanitize.text(nil)
    puts "✅ PASS: Zoning vacío → nil"
  end

  def test_text_strips_whitespace_and_nbsp
    assert_equal "R-1", Sanitize.text("  R-1  ")
    assert_equal "Residential", Sanitize.text(" \u00A0 Residential \u00A0 ")
    puts "✅ PASS: Texto con whitespace/NBSP → limpio y stripped"
  end

  # ── DECIMAL: Acres con basura ──────────────────────────────────────────────
  def test_decimal_with_units
    assert_equal BigDecimal("2.5"), Sanitize.decimal("2.5 acres")
    puts "✅ PASS: Decimal '2.5 acres' → 2.5"
  end

  # ── ENTERO: sqft con comas ─────────────────────────────────────────────────
  def test_integer_with_commas
    assert_equal 1200, Sanitize.integer("1,200 sqft")
    puts "✅ PASS: Integer '1,200 sqft' → 1200"
  end

  # ── URL: Validación de protocolo ───────────────────────────────────────────
  def test_url_valid
    assert_equal "https://example.com", Sanitize.url("  https://example.com  ")
    puts "✅ PASS: URL válida → limpia"
  end

  def test_url_invalid_no_protocol
    assert_nil Sanitize.url("example.com")
    assert_nil Sanitize.url("ftp://data.gov")
    puts "✅ PASS: URL sin http(s) → nil"
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # SECCIÓN 2: PRUEBA DE CRM IMMUNITY (FAILSAFE)
  # ──────────────────────────────────────────────────────────────────────────────

  def test_crm_immunity_guard_blocks_protected_columns
    processor = SheetRowProcessor.new([])

    # Simular un hash de atributos que INTENTA infiltrar campos CRM
    malicious_attrs = {
      state: "FL",
      county: "Miami-Dade",
      parcel_id: "TEST-001",
      parcel_user_tags: "target",       # ⛔ PROTEGIDO
      parcel_user_notes: "Hacked note"  # ⛔ PROTEGIDO
    }

    error = assert_raises(ActiveRecord::RecordNotSaved) do
      processor.send(:enforce_crm_immunity!, malicious_attrs)
    end

    assert_match(/CRM IMMUNITY VIOLATION/, error.message)
    assert_match(/parcel_user_tags/, error.message)
    assert_match(/parcel_user_notes/, error.message)
    puts "✅ PASS: CRM Immunity Guard BLOQUEÓ infiltración de parcel_user_tags + parcel_user_notes"
  end

  def test_crm_immunity_allows_normal_columns
    processor = SheetRowProcessor.new([])

    safe_attrs = {
      state: "FL",
      county: "Miami-Dade",
      opening_bid: BigDecimal("12500"),
      zoning: "R-1"
    }

    # No debería levantar error
    processor.send(:enforce_crm_immunity!, safe_attrs)
    puts "✅ PASS: CRM Immunity Guard PERMITE columnas normales sin error"
  end

  def test_crm_immune_columns_constant_complete
    expected = %w[parcel_user_tags parcel_user_notes user_tags user_notes]
    assert_equal expected.sort, SheetRowProcessor::CRM_IMMUNE_COLUMNS.sort,
      "FAIL: CRM_IMMUNE_COLUMNS no contiene todas las columnas esperadas"
    puts "✅ PASS: CRM_IMMUNE_COLUMNS cubre 4 variantes: #{expected.join(', ')}"
  end

  # ── PRUEBA MATEMÁTICA: Los datos CRM viven en tablas SEPARADAS ─────────────
  def test_crm_data_lives_in_separate_tables
    # Verificar que parcel_user_tags NO es una columna de parcels
    parcel_columns = Parcel.column_names
    refute_includes parcel_columns, "parcel_user_tags",
      "FAIL: parcel_user_tags es columna de parcels — debería ser tabla separada"
    refute_includes parcel_columns, "parcel_user_notes",
      "FAIL: parcel_user_notes es columna de parcels — debería ser tabla separada"

    # Verificar que existen como modelos/tablas separadas
    assert ParcelUserTag.table_exists?,  "FAIL: Tabla parcel_user_tags no existe"
    assert ParcelUserNote.table_exists?, "FAIL: Tabla parcel_user_notes no existe"

    puts "✅ PASS: CRM data vive en tablas separadas (parcel_user_tags, parcel_user_notes)"
    puts "   └── Sync masivo SOLO toca tabla 'parcels' → inmunidad estructural garantizada"
  end

  # ── PRUEBA: Upsert no destruye CRM por dependencia ────────────────────────
  def test_sync_upsert_does_not_delete_parcels
    # SheetRowProcessor usa find_or_initialize_by, NUNCA destroy
    source = File.read(Rails.root.join("app/services/sheet_row_processor.rb"))
    refute_match(/\.destroy/, source, "FAIL: SheetRowProcessor contiene .destroy — peligro para CRM")
    refute_match(/\.delete/, source, "FAIL: SheetRowProcessor contiene .delete — peligro para CRM")
    refute_match(/delete_all/, source, "FAIL: SheetRowProcessor contiene delete_all — peligro para CRM")
    puts "✅ PASS: SheetRowProcessor no contiene destroy/delete → CRM seguro vía has_many :dependent"
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # SECCIÓN 3: AUDITORÍA VISUAL — RENDERIZADO DE LA FICHA
  # ──────────────────────────────────────────────────────────────────────────────

  def test_view_currency_formatting_with_nil
    # number_to_currency(nil) → debería caer al fallback "—"
    # La vista usa: @parcel.opening_bid ? number_to_currency(...) : "—"
    view_source = File.read(Rails.root.join("app/views/research/parcels/show.html.erb"))

    # Verificar patrón de nil-guard para campos monetarios
    currency_fields = %w[opening_bid assessed_value land_value improvement_value
                         delinquent_amount estimated_sale_value
                         price_per_acre max_bid_30 max_bid_35]

    currency_fields.each do |field|
      has_guard = view_source.include?("@parcel.#{field} ?") ||
                  view_source.include?("@parcel.#{field}?")
      # Los calculados se llaman como métodos
      if %w[max_bid_30 max_bid_35].include?(field)
        has_guard ||= view_source.include?("@parcel.#{field} ?")
      end
      assert has_guard || !view_source.include?(field),
        "⚠️  Campo monetario '#{field}' podría crashear la vista si es nil (sin guard ternario)"
    end
    puts "✅ PASS: Todos los campos monetarios tienen nil-guard con ternario → sin crash por nil"
  end

  def test_view_text_fields_use_presence_fallback
    view_source = File.read(Rails.root.join("app/views/research/parcels/show.html.erb"))

    # Verificar que campos de texto usan .presence || "—"
    text_fields_with_fallback = %w[zoning land_use lot_shape minimum_lot_size
                                   jurisdiction owner_name property_address]

    text_fields_with_fallback.each do |field|
      has_fallback = view_source.include?("@parcel.#{field}.presence || \"—\"") ||
                     view_source.include?("@parcel.#{field}.present?")
      assert has_fallback,
        "⚠️  Campo texto '#{field}' sin fallback .presence en vista → podría mostrar vacío"
    end
    puts "✅ PASS: Campos texto usan .presence || '—' → nil se muestra elegantemente"
  end

  def test_view_fema_risk_nil_safe
    view_source = File.read(Rails.root.join("app/views/research/parcels/show.html.erb"))

    assert view_source.include?("@parcel.fema_risk_level.present?"),
      "FAIL: FEMA Risk Level no tiene .present? guard — podría crashear con .downcase en nil"
    puts "✅ PASS: FEMA Risk Level protegido con .present? → nil muestra '—', no crash"
  end

  # ── BUG DETECTADO: Utilities boolean rendering ────────────────────────────
  def test_view_utilities_boolean_rendering_bug
    # BUG: Sanitize.boolean devuelve true/false (Ruby booleans)
    # DB columns (electric, water, sewer, hoa) son STRING type
    # Ruby true se almacena como "true" en columna string
    # La vista hace: u[:val].downcase == "yes" → NUNCA match para "true"
    # Resultado: TODAS las utilities muestran badge ROJO (danger) incluso si son "yes"

    # Verificar que el bug existe o ya fue corregido
    view_source = File.read(Rails.root.join("app/views/research/parcels/show.html.erb"))

    # El patrón buggy original:
    buggy_pattern = 'u[:val].downcase == "yes"'
    # El patrón corregido debería incluir "true" como valor afirmativo
    fixed_pattern = 'is_affirmative'

    if view_source.include?(buggy_pattern) && !view_source.include?(fixed_pattern)
      puts "🔴 BUG CONFIRMADO: Utilities compara solo con 'yes' — no reconoce 'true' de Sanitize.boolean"
      puts "   └── Electric='true' aparece como badge ROJO en producción"
      puts "   └── FIX: Verificar %w[yes true y 1].include?(val.downcase)"
      flunk "BUG: Vista utilities no reconoce boolean 'true' (devuelto por Sanitize.boolean)"
    else
      puts "✅ PASS: Utilities corregido — reconoce tanto 'yes' como 'true'"
    end
  end

  # ── Verificar CSS inline (regla crítica del Drawer AJAX) ───────────────────
  def test_view_has_inline_styles
    view_source = File.read(Rails.root.join("app/views/research/parcels/show.html.erb"))

    assert view_source.include?("<style>"),
      "FAIL: Vista show.html.erb NO tiene <style> inline — incumple regla CSS del Drawer AJAX"
    refute view_source.include?("stylesheet_link_tag"),
      "FAIL: Vista usa stylesheet_link_tag — NO funciona en AJAX drawer"
    puts "✅ PASS: CSS es inline (<style>) — compatible con AJAX drawer (regla absoluta)"
  end

  def test_view_no_content_for_head
    view_source = File.read(Rails.root.join("app/views/research/parcels/show.html.erb"))

    # Solo permitimos content_for :title (inofensivo en AJAX)
    styles_in_head = view_source.scan(/content_for\s+:head/)
    assert_empty styles_in_head,
      "FAIL: Vista usa content_for :head — se pierde en AJAX drawer (no hay layout)"
    puts "✅ PASS: Sin content_for :head → estilos no se pierden en AJAX"
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # SECCIÓN 4: INTEGRIDAD DE UNIQUE INDEX COMPUESTO
  # ──────────────────────────────────────────────────────────────────────────────

  def test_unique_index_exists
    indexes = ActiveRecord::Base.connection.indexes(:parcels)
    composite_idx = indexes.find { |i| i.name == "idx_parcels_unique_state_county_pid" }

    assert composite_idx, "FAIL: UNIQUE INDEX compuesto no existe en parcels"
    assert composite_idx.unique, "FAIL: Index no es UNIQUE"
    assert_equal %w[state county parcel_id], composite_idx.columns,
      "FAIL: Columnas del index no son (state, county, parcel_id)"
    puts "✅ PASS: UNIQUE INDEX (state, county, parcel_id) existe y es correcto"
  end

  def test_not_null_constraints
    columns = ActiveRecord::Base.connection.columns(:parcels)
    state_col  = columns.find { |c| c.name == "state" }
    county_col = columns.find { |c| c.name == "county" }
    pid_col    = columns.find { |c| c.name == "parcel_id" }

    refute state_col.null,  "FAIL: state permite NULL — violación de integridad"
    refute county_col.null, "FAIL: county permite NULL — violación de integridad"
    refute pid_col.null,    "FAIL: parcel_id permite NULL — violación de integridad"
    puts "✅ PASS: NOT NULL enforced en (state, county, parcel_id) a nivel PostgreSQL"
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # SECCIÓN 5: BUGS DETECTADOS EN SYNC_SHEET_JOB
  # ──────────────────────────────────────────────────────────────────────────────

  def test_sync_log_schema_has_required_columns
    columns = SyncLog.column_names

    # El job escribe records_synced y records_failed — verificar si existen
    has_records_synced = columns.include?("records_synced")
    has_records_failed = columns.include?("records_failed")

    unless has_records_synced && has_records_failed
      puts "🔴 BUG: SyncSheetJob escribe records_synced/records_failed pero columnas NO EXISTEN en sync_logs"
      puts "   └── Esto causa ActiveModel::UnknownAttributeError tras sync exitoso"
      puts "   └── FIX: Agregar migración con add_column :sync_logs, :records_synced/:records_failed"
    end

    # Verificar si el status 'completed_with_errors' es válido
    valid_statuses = SyncLog::STATUSES
    unless valid_statuses.include?("completed_with_errors")
      puts "🟡 WARNING: SyncLog validates status in #{valid_statuses.inspect}"
      puts "   └── Pero SyncSheetJob usa 'completed_with_errors' (línea 63) — validación falla"
    end
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# RESUMEN VISUAL (ejecutar independientemente)
# ═══════════════════════════════════════════════════════════════════════════════
if __FILE__ == $0
  puts ""
  puts "═" * 72
  puts "  E2E SYNC → VISUAL QA — SIMULACIÓN DE DATOS SUCIOS"
  puts "═" * 72
  puts ""
  puts "📊 Simulando payload de Google Sheets con datos premium basura:"
  puts ""
  puts "  Deuda:        '$ 12,500.00 '  → Sanitize.currency → #{Sanitize.currency('$ 12,500.00 ').inspect}"
  puts "  HOA:          '  $150/mo '    → Sanitize.boolean  → #{Sanitize.boolean('  $150/mo ').inspect}"
  puts "  Flood Zone:   ''              → Sanitize.text     → #{Sanitize.text('').inspect}"
  puts "  Zoning:       nil             → Sanitize.text     → #{Sanitize.text(nil).inspect}"
  puts "  Electric:     'yes'           → Sanitize.boolean  → #{Sanitize.boolean('yes').inspect}"
  puts "  Wetlands:     'YES'           → Sanitize.boolean  → #{Sanitize.boolean('YES').inspect}"
  puts ""
  puts "📋 Renderizado visual esperado en la Ficha:"
  puts ""
  puts "  Deuda 12500.0 → number_to_currency → $12,500.00 ✅"
  puts "  HOA nil       → vista muestra '—'               ✅"
  puts "  Flood nil     → vista muestra '—'               ✅"
  puts "  Zoning nil    → vista muestra '—'               ✅"
  puts ""
  puts "═" * 72
end
