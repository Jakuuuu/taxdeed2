# frozen_string_literal: true

# GoogleSheetsImporter — Lee filas del Google Sheet de propiedades
#
# Autenticación: Google Service Account (JSON en credentials.yml.enc o archivo local)
# Scope:         spreadsheets.readonly
#
# Pestañas soportadas:
#   - "Propiedades1" — Parcelas de subastas (existente)
#   - "Condados"     — Info macro del condado (Rama 4)
#   - "Mercados"     — Volumen inmobiliario mensual (Rama 4)
#
# 🛡️ HEADER FAILSAFE:
#   validate_headers! verifica la presencia de columnas maestras (State, County,
#   Parcel Number) ANTES de leer datos. Si faltan → SheetSchemaError + SyncLog
#   + abort total. Sin este guard, el mapeo posicional corrompe datos.
#
# 🛡️ MAPEO RESILIENTE:
#   fetch_headers_and_rows normaliza cabeceras con .strip + NBSP removal
#   para eliminar caracteres invisibles que podrían romper el mapeo.
#
# 🔑 CREDENCIALES (v2 — Resilient Key Loading):
#   Carga la private key desde 3 fuentes en orden de prioridad:
#     1. ENV['GOOGLE_APPLICATION_CREDENTIALS'] (archivo JSON en disco)
#     2. ENV['GOOGLE_CREDENTIALS_JSON'] (JSON inline — Render/Docker)
#     3. Rails.application.credentials.google_service_account (credentials.yml.enc)
#   La fuente #1 es la más fiable porque el JSON se lee tal cual sin
#   riesgo de corrupción por re-encoding YAML/credentials edit.
#
# 🚀 MEMORY-SAFE STREAMING (v3):
#   fetch_rows_in_chunks lee el Sheet en ventanas de CHUNK_SIZE filas,
#   yieldeando cada lote al caller para procesamiento inmediato.
#   Esto reduce la huella de memoria de O(N) a O(CHUNK_SIZE).
#
class GoogleSheetsImporter
  # ── Pestañas del Sheet ──────────────────────────────────────────────────
  SHEET_TAB  = "Propiedades1"  # ⚠️ Nombre exacto de la pestaña en el Sheet
  COUNTIES_TAB = "Condados"    # Rama 4: Info macro del condado
  MARKETS_TAB  = "Mercados"    # Rama 4: Volumen inmobiliario mensual

  # ── Rangos para la pestaña principal (Propiedades) ────────────────────
  DATA_RANGE = "#{SHEET_TAB}!A2:CD"
  HEADER_RANGE = "#{SHEET_TAB}!A1:CD1"

  # ── Rangos para Condados (hasta columna AI = 35 columnas) ─────────────
  COUNTIES_HEADER_RANGE = "#{COUNTIES_TAB}!A1:AI1"
  COUNTIES_DATA_RANGE   = "#{COUNTIES_TAB}!A2:AI"

  # ── Rangos para Mercados (TABLA CRUZADA HORIZONTAL) ───────────────────
  # Fila 1: título "Mes de Period End" (ignorar)
  # Fila 2: vacía (ignorar)
  # Fila 3: Headers reales: Estado | Condados | Enero de 2012 | Feb... | ...
  # Fila 4+: Datos: Florida | Alachua | $164,950.00 | ...
  # Ancho: ~172 columnas (2 id + 170 meses)
  MARKETS_HEADER_RANGE  = "#{MARKETS_TAB}!A3:ZZ3"   # Fila 3 = headers de fechas
  MARKETS_DATA_RANGE    = "#{MARKETS_TAB}!A4:ZZ"     # Fila 4+ = datos

  # ── 🚀 STREAMING: Tamaño de ventana para paginación por rangos ────────────
  # Cada request al API de Google Sheets pide CHUNK_SIZE filas.
  # En memoria solo vive 1 chunk a la vez + overhead del service object.
  CHUNK_SIZE = 200

  # ── 🛡️ HEADER FAILSAFE ──────────────────────────────────────────────────────
  # Headers OBLIGATORIOS para que el sync proceda.
  # Si alguno falta o fue renombrado → ABORT total + SyncLog.
  #
  # El Sheet real usa headers en español (\"Estado\", \"Condado\") pero el código
  # original esperaba inglés (\"State\", \"County\"). Se aceptan ambas variantes.
  REQUIRED_HEADERS = {
    "State/Estado"         => %w[state estado],
    "County/Condado"       => %w[county condado],
    "Parcel Number"        => ["parcel number"]
  }.freeze

  # Exception dedicada para errores de esquema del Sheet
  class SheetSchemaError < StandardError; end

  # Retorna solo filas de datos (compatibilidad legacy)
  def self.fetch_rows(sheet_id)
    service = build_service
    response = service.get_spreadsheet_values(sheet_id, DATA_RANGE)
    response.values || []
  rescue Google::Apis::AuthorizationError => e
    Rails.logger.error "[GoogleSheetsImporter] Auth error: #{e.message}"
    raise
  rescue Google::Apis::ClientError => e
    Rails.logger.error "[GoogleSheetsImporter] Client error: #{e.message}"
    raise
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 🚀 MEMORY-SAFE: Streaming por ventanas de rango
  #
  # En vez de cargar TODAS las filas en un Array gigante, este método:
  #   1. Valida headers (fila 1)
  #   2. Lee filas en ventanas de CHUNK_SIZE (A2:CB201, A202:CB401, ...)
  #   3. Yield cada chunk al bloque del caller
  #   4. Cada chunk es eligible para GC después del yield
  #
  # Uso:
  #   GoogleSheetsImporter.fetch_rows_in_chunks(sheet_id) do |chunk, chunk_index|
  #     chunk.each { |row| SheetRowProcessor.process(row) }
  #   end
  #
  # Reduce memoria de O(total_rows) a O(CHUNK_SIZE).
  # ═══════════════════════════════════════════════════════════════════════════
  def self.fetch_rows_in_chunks(sheet_id, chunk_size: CHUNK_SIZE)
    Rails.logger.info "[GoogleSheetsImporter] 🔍 DIAGNOSTIC: sheet_id=#{sheet_id.inspect}, " \
                      "tab=#{SHEET_TAB}, header_range=#{HEADER_RANGE}, chunk_size=#{chunk_size}"

    service = build_service

    # ── Paso 1: Validar headers ────────────────────────────────────────────
    header_response = service.get_spreadsheet_values(sheet_id, HEADER_RANGE)
    raw_headers = header_response.values&.first || []
    normalized_headers = raw_headers.map { |h| h.to_s.strip.gsub(/\u00A0/, " ").strip }
    validate_headers!(normalized_headers)

    # 🔍 DIAGNOSTIC: Dump header positions to identify column shifts
    header_map = normalized_headers.each_with_index.map { |h, i| "#{i}=#{h}" }.first(25)
    Rails.logger.info "[GoogleSheetsImporter] 🗺️ HEADER MAP: #{header_map.join(' | ')}"
    Rails.logger.info "[GoogleSheetsImporter] 🛡️ Headers validados OK (#{normalized_headers.size} columnas)"

    # ── Paso 2: Iterar por ventanas de rango ───────────────────────────────
    row_offset = 2
    chunk_index = 0
    total_rows_fetched = 0

    loop do
      start_row = row_offset + (chunk_index * chunk_size)
      end_row   = start_row + chunk_size - 1
      range     = "#{SHEET_TAB}!A#{start_row}:CD#{end_row}"

      Rails.logger.info "[GoogleSheetsImporter] 📦 Fetching chunk #{chunk_index + 1}: rows #{start_row}–#{end_row}"

      response = service.get_spreadsheet_values(sheet_id, range)
      rows = response.values || []

      break if rows.empty?

      total_rows_fetched += rows.size

      # 🔍 DIAGNOSTIC: Log first row of first chunk to verify column alignment
      if chunk_index == 0 && rows.any?
        sample = rows.first.each_with_index.map { |v, i| "#{i}=#{v.to_s.truncate(25)}" }.first(15)
        Rails.logger.info "[GoogleSheetsImporter] 🔬 FIRST ROW DATA: #{sample.join(' | ')}"
      end

      # Yield el chunk al caller — después del yield, `rows` es eligible para GC
      yield rows, chunk_index

      # Si recibimos menos filas que el chunk_size, llegamos al final del Sheet
      break if rows.size < chunk_size

      chunk_index += 1
    end

    Rails.logger.info "[GoogleSheetsImporter] ✅ Streaming completo: #{total_rows_fetched} filas en #{chunk_index + 1} chunks"

    { headers: normalized_headers, total_rows: total_rows_fetched, total_chunks: chunk_index + 1 }
  rescue Google::Apis::AuthorizationError => e
    Rails.logger.error "[GoogleSheetsImporter] 🔐 Auth error: #{e.message}"
    Rails.logger.error "[GoogleSheetsImporter]    status_code=#{e.status_code rescue 'N/A'}, body=#{e.body rescue 'N/A'}"
    raise
  rescue Google::Apis::ClientError => e
    Rails.logger.error "[GoogleSheetsImporter] ❌ Client error: #{e.message}"
    Rails.logger.error "[GoogleSheetsImporter]    status_code=#{e.status_code rescue 'N/A'}"
    Rails.logger.error "[GoogleSheetsImporter]    body=#{e.body rescue 'N/A'}"
    Rails.logger.error "[GoogleSheetsImporter]    sheet_id=#{sheet_id.inspect}"
    Rails.logger.error "[GoogleSheetsImporter]    backtrace=#{e.backtrace&.first(5)&.join("\n")}"
    raise
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 🏛️ RAMA 4: Streaming para pestaña "Condados"
  #
  # Mismo patrón memory-safe que Propiedades.
  # Valida headers propios (State/County obligatorios).
  # ═══════════════════════════════════════════════════════════════════════════
  def self.fetch_counties_in_chunks(sheet_id, chunk_size: CHUNK_SIZE)
    Rails.logger.info "[GoogleSheetsImporter] 🏛️ Streaming pestaña: #{COUNTIES_TAB}"

    service = build_service

    # Validar headers de Condados (fila 1)
    header_response = service.get_spreadsheet_values(sheet_id, COUNTIES_HEADER_RANGE)
    raw_headers = header_response.values&.first || []
    normalized = raw_headers.map { |h| h.to_s.strip.gsub(/\u00A0/, " ").strip }
    validate_tab_headers_by_position!(normalized, CountySheetColumnMap::REQUIRED_HEADERS, COUNTIES_TAB)

    Rails.logger.info "[GoogleSheetsImporter] 🛡️ Condados headers OK (#{normalized.size} columnas)"

    stream_tab(service, sheet_id, COUNTIES_TAB, "AI", chunk_size: chunk_size) do |chunk, idx|
      yield chunk, idx
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 📊 RAMA 4: Streaming para pestaña "Mercados"
  #
  # Mismo patrón memory-safe. Datos de timeseries financiero.
  # ═══════════════════════════════════════════════════════════════════════════
  # ═══════════════════════════════════════════════════════════════════════════
  # 📊 RAMA 4: Pestaña "Mercados" — TABLA CRUZADA HORIZONTAL
  #
  # Esta pestaña NO es una tabla normal. Es una pivot table:
  #   - Fila 3 contiene los headers de fechas ("Enero de 2012", "Febrero de 2012"...)
  #   - Fila 4+ contiene datos: Estado | Condado | $valor_mes1 | $valor_mes2 | ...
  #
  # Este método:
  #   1. Lee fila 3 para extraer las fechas de columna
  #   2. Parsea cada fecha ("Enero de 2012" → Date)
  #   3. Retorna las fechas parseadas + yield de chunks de datos (fila 4+)
  # ═══════════════════════════════════════════════════════════════════════════
  def self.fetch_markets_in_chunks(sheet_id, chunk_size: CHUNK_SIZE)
    Rails.logger.info "[GoogleSheetsImporter] 📊 Streaming pestaña: #{MARKETS_TAB} (PIVOT TABLE)"

    service = build_service

    # ── Paso 1: Leer fila 3 (headers de fechas) ──────────────────────────
    header_response = service.get_spreadsheet_values(sheet_id, MARKETS_HEADER_RANGE)
    raw_headers = header_response.values&.first || []
    normalized = raw_headers.map { |h| h.to_s.strip.gsub(/\u00A0/, " ").strip }

    # Validar que las 2 primeras columnas sean Estado y Condados
    validate_tab_headers_by_position!(normalized, MarketSheetColumnMap::REQUIRED_HEADERS, MARKETS_TAB)

    # ── Paso 2: Parsear las fechas de las columnas C en adelante ─────────
    date_columns = normalized[MarketSheetColumnMap::DATES_START_COL..] || []
    date_headers = date_columns.map { |h| MarketSheetColumnMap.parse_month_header(h) }

    valid_dates = date_headers.compact.size
    Rails.logger.info "[GoogleSheetsImporter] 📅 Mercados: #{date_columns.size} columnas de fecha, " \
                      "#{valid_dates} parseadas OK"
    Rails.logger.info "[GoogleSheetsImporter] 📅 Rango: #{date_headers.compact.first} → #{date_headers.compact.last}"

    # ── Paso 3: Streaming de datos (fila 4+) ─────────────────────────────
    # Nota: stream_tab_from usa fila 4 como inicio, no fila 2
    stream_tab(service, sheet_id, MARKETS_TAB, "ZZ",
              chunk_size: chunk_size, data_start_row: 4) do |chunk, idx|
      yield chunk, idx, date_headers
    end
  end

  # 🛡️ MAPEO RESILIENTE (LEGACY — carga TODO en memoria)
  # ⚠️ DEPRECADO para producción: usar fetch_rows_in_chunks para Memory-Safe.
  # Mantenido para tests y desarrollo local con datasets pequeños.
  def self.fetch_headers_and_rows(sheet_id)
    service = build_service

    # Fetch cabeceras (fila 1)
    header_response = service.get_spreadsheet_values(sheet_id, HEADER_RANGE)
    raw_headers = header_response.values&.first || []
    # 🛡️ Normalizar: eliminar NBSP, trailing spaces, tabs, BOM
    normalized_headers = raw_headers.map { |h| h.to_s.strip.gsub(/\u00A0/, " ").strip }

    # 🛡️ VALIDACIÓN DE ESQUEMA — Antes de leer datos
    validate_headers!(normalized_headers)

    # Fetch datos (fila 2+)
    data_response = service.get_spreadsheet_values(sheet_id, DATA_RANGE)
    rows = data_response.values || []

    { headers: normalized_headers, rows: rows }
  rescue Google::Apis::AuthorizationError => e
    Rails.logger.error "[GoogleSheetsImporter] Auth error: #{e.message}"
    raise
  rescue Google::Apis::ClientError => e
    Rails.logger.error "[GoogleSheetsImporter] Client error: #{e.message}"
    raise
  end

  # ── 🛡️ GUARDIÁN DE ESQUEMA ─────────────────────────────────────────────────
  # Verifica que las columnas maestras existan en los headers del Sheet.
  # Si faltan → raise SheetSchemaError + log en SyncLog + NO procesar filas.
  #
  # Comparación case-insensitive + stripped para tolerar variaciones menores
  # pero NO tolera la ausencia total de una columna maestra.
  # Acepta variantes en español e inglés (e.g., "State" OR "Estado").
  def self.validate_headers!(headers)
    normalized_set = headers.map { |h| h.to_s.strip.downcase }

    missing = REQUIRED_HEADERS.reject do |_label, variants|
      variants.any? { |v| normalized_set.include?(v) }
    end.keys

    return if missing.empty?

    error_msg = "[SCHEMA FAILSAFE] Headers maestros ausentes: #{missing.join(', ')}. " \
                "El Sheet fue modificado o las columnas fueron renombradas. " \
                "Sync ABORTADO para proteger integridad de datos."

    # Registrar fallo en SyncLog para auditoría desde Admin Dashboard
    if defined?(SyncLog)
      SyncLog.create!(
        status:         "failed",
        error_message:  error_msg,
        started_at:     Time.current,
        completed_at:   Time.current
      )
    end

    Rails.logger.fatal error_msg
    raise SheetSchemaError, error_msg
  end

  # ── Validación por posición para pestañas Rama 4 ───────────────────────
  # required_map = { position => expected_header_name } (e.g., { 0 => "ESTADO", 2 => "CONDADO" })
  def self.validate_tab_headers_by_position!(headers, required_map, tab_name)
    mismatches = []

    required_map.each do |position, expected|
      actual = headers[position]&.to_s&.strip&.upcase
      expected_upper = expected.to_s.strip.upcase
      unless actual == expected_upper
        mismatches << "Col #{position}: expected '#{expected}', got '#{actual}'"
      end
    end

    return if mismatches.empty?

    error_msg = "[SCHEMA FAILSAFE] Headers incorrectos en pestaña '#{tab_name}': #{mismatches.join('; ')}. " \
                "Sync de #{tab_name} ABORTADO."

    Rails.logger.error error_msg
    raise SheetSchemaError, error_msg
  end

  def self.build_service
    service = Google::Apis::SheetsV4::SheetsService.new
    service.authorization = google_credentials
    service
  end
  private_class_method :build_service

  # ═══════════════════════════════════════════════════════════════════════════
  # 🔗 RAMA 4: Extracción de Hyperlinks para pestaña "Condados"
  #
  # La API values.get solo devuelve el texto visible ("Link", "imagen").
  # Para obtener las URLs reales embebidas en celdas con hiperenlace,
  # usamos spreadsheets.get con field mask que incluye 'hyperlink'.
  #
  # Retorna un Hash de hyperlinks:
  #   { row_index => { col_index => "https://real-url.com" } }
  # ═══════════════════════════════════════════════════════════════════════════
  def self.fetch_county_hyperlinks(sheet_id)
    Rails.logger.info "[GoogleSheetsImporter] 🔗 Fetching hyperlinks from #{COUNTIES_TAB}"

    service = build_service

    range = "#{COUNTIES_TAB}!A2:AI"

    response = service.get_spreadsheet(
      sheet_id,
      ranges: [range],
      fields: 'sheets/data/rowData/values(hyperlink,formattedValue)'
    )

    hyperlinks = {}

    sheet_data = response.sheets&.first&.data&.first
    return hyperlinks unless sheet_data&.row_data

    sheet_data.row_data.each_with_index do |row, row_idx|
      next unless row&.values

      row.values.each_with_index do |cell, col_idx|
        next unless cell&.hyperlink.present?

        hyperlinks[row_idx] ||= {}
        hyperlinks[row_idx][col_idx] = cell.hyperlink
      end
    end

    total_links = hyperlinks.values.sum { |h| h.size }
    Rails.logger.info "[GoogleSheetsImporter] 🔗 Extracted #{total_links} hyperlinks from #{hyperlinks.size} rows"

    hyperlinks
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 🔗 Extracción de Hyperlinks para pestaña "Propiedades1"
  #
  # Mismo patrón que fetch_county_hyperlinks. Las celdas con =HYPERLINK(...)
  # muestran "Link" como texto visible pero la URL real está en los metadatos.
  #
  # Retorna Hash: { row_index => { col_index => "https://real-url.com" } }
  # donde row_index es 0-indexed relativo a fila 2 del Sheet.
  # ═══════════════════════════════════════════════════════════════════════════
  def self.fetch_property_hyperlinks(sheet_id)
    Rails.logger.info "[GoogleSheetsImporter] 🔗 Fetching hyperlinks from #{SHEET_TAB}"

    service = build_service

    range = "#{SHEET_TAB}!A2:CD"

    response = service.get_spreadsheet(
      sheet_id,
      ranges: [range],
      fields: 'sheets/data/rowData/values(hyperlink,formattedValue)'
    )

    hyperlinks = {}

    sheet_data = response.sheets&.first&.data&.first
    return hyperlinks unless sheet_data&.row_data

    sheet_data.row_data.each_with_index do |row, row_idx|
      next unless row&.values

      row.values.each_with_index do |cell, col_idx|
        next unless cell&.hyperlink.present?

        hyperlinks[row_idx] ||= {}
        hyperlinks[row_idx][col_idx] = cell.hyperlink
      end
    end

    total_links = hyperlinks.values.sum { |h| h.size }
    Rails.logger.info "[GoogleSheetsImporter] 🔗 Extracted #{total_links} property hyperlinks from #{hyperlinks.size} rows"

    hyperlinks
  end

  # ── Streaming genérico para cualquier pestaña ──────────────────────────
  # data_start_row: fila del Sheet donde empiezan los datos (default: 2)
  def self.stream_tab(service, sheet_id, tab_name, last_col, chunk_size: CHUNK_SIZE, data_start_row: 2)
    chunk_index = 0
    total = 0

    loop do
      start_row = data_start_row + (chunk_index * chunk_size)
      end_row   = start_row + chunk_size - 1
      range     = "#{tab_name}!A#{start_row}:#{last_col}#{end_row}"

      Rails.logger.info "[GoogleSheetsImporter] 📦 #{tab_name} chunk #{chunk_index + 1}: rows #{start_row}–#{end_row}"

      response = service.get_spreadsheet_values(sheet_id, range)
      rows = response.values || []

      break if rows.empty?

      total += rows.size
      yield rows, chunk_index

      break if rows.size < chunk_size
      chunk_index += 1
    end

    Rails.logger.info "[GoogleSheetsImporter] ✅ #{tab_name} completo: #{total} filas en #{chunk_index + 1} chunks"
    { total_rows: total, total_chunks: chunk_index + 1 }
  end
  private_class_method :stream_tab

  # ═══════════════════════════════════════════════════════════════════════════
  # 🔑 CREDENCIALES — Resilient Key Loading (v2)
  #
  # Prioridad de carga:
  #   1. Archivo JSON en disco (GOOGLE_APPLICATION_CREDENTIALS) — más fiable
  #   2. JSON inline en ENV (GOOGLE_CREDENTIALS_JSON) — para Render/Docker
  #   3. Rails credentials (credentials.yml.enc) — fallback
  #
  # La fuente #1 elimina el riesgo de corrupción de la private key
  # durante `rails credentials:edit` (bug original: base64 corruption).
  # ═══════════════════════════════════════════════════════════════════════════
  def self.google_credentials
    json_key = resolve_credentials_json

    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(json_key),
      scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY
    )
  end
  private_class_method :google_credentials

  # Resuelve el JSON de credenciales desde la fuente disponible
  def self.resolve_credentials_json
    # ── Fuente 1: Archivo JSON en disco ──────────────────────────────────────
    json_path = ENV["GOOGLE_APPLICATION_CREDENTIALS"]
    if json_path.present? && File.exist?(json_path)
      Rails.logger.info "[GoogleSheetsImporter] 🔑 Using credentials from file: #{json_path}"
      return File.read(json_path)
    end

    # ── Fuente 2: JSON inline en ENV (Render/Docker) ─────────────────────────
    if ENV["GOOGLE_CREDENTIALS_JSON"].present?
      Rails.logger.info "[GoogleSheetsImporter] 🔑 Using inline credentials from GOOGLE_CREDENTIALS_JSON"
      return ENV["GOOGLE_CREDENTIALS_JSON"]
    end

    # ── Fuente 3: Rails credentials (fallback) ───────────────────────────────
    creds_hash = Rails.application.credentials.google_service_account
    raise "Missing Google Service Account credentials. Set GOOGLE_APPLICATION_CREDENTIALS, " \
          "GOOGLE_CREDENTIALS_JSON, or configure google_service_account in credentials.yml.enc" if creds_hash.blank?

    Rails.logger.info "[GoogleSheetsImporter] 🔑 Using credentials from Rails credentials.yml.enc"

    # Normalizar la private key: si Rails credentials almacenó la key con
    # newlines reales, el JSON la necesita con \n escapados para que
    # google-auth pueda parsearla correctamente.
    normalized = creds_hash.deep_dup
    if normalized[:private_key].present?
      pk = normalized[:private_key].to_s
      # Si la key ya tiene newlines reales (no escapados), re-empaquetar
      unless pk.include?('\\n') && !pk.include?("\n")
        # Key tiene newlines reales — convertir a formato JSON standard
        pk = pk.gsub("\r\n", "\n").gsub("\r", "\n")
      end
      normalized[:private_key] = pk
    end

    normalized.transform_keys(&:to_s).to_json
  end
  private_class_method :resolve_credentials_json
end
