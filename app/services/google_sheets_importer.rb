# frozen_string_literal: true

# GoogleSheetsImporter — Lee filas del Google Sheet de propiedades
#
# Autenticación: Google Service Account (JSON en credentials.yml.enc o archivo local)
# Scope:         spreadsheets.readonly
# Sheet tab:     "Propiedades" (pestaña real del Sheet de producción)
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
class GoogleSheetsImporter
  SHEET_TAB  = "Propiedades"  # ⚠️ Nombre exacto de la pestaña en el Sheet
  DATA_RANGE = "#{SHEET_TAB}!A2:CB"
  HEADER_RANGE = "#{SHEET_TAB}!A1:CB1"

  # ── 🛡️ HEADER FAILSAFE ──────────────────────────────────────────────────────
  # Headers OBLIGATORIOS para que el sync proceda.
  # Si alguno falta o fue renombrado → ABORT total + SyncLog.
  #
  # El Sheet real usa headers en español ("Estado", "Condado") pero el código
  # original esperaba inglés ("State", "County"). Se aceptan ambas variantes.
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

  # 🛡️ MAPEO RESILIENTE: Retorna { headers: [...], rows: [...] }
  # Las cabeceras se normalizan con .strip + eliminación de NBSP.
  # ⛔ ABORTA si headers maestros faltan (validate_headers!)
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

  def self.build_service
    service = Google::Apis::SheetsV4::SheetsService.new
    service.authorization = google_credentials
    service
  end
  private_class_method :build_service

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
      unless pk.include?('\n') && !pk.include?("\n")
        # Key tiene newlines reales — convertir a formato JSON standard
        pk = pk.gsub("\r\n", "\n").gsub("\r", "\n")
      end
      normalized[:private_key] = pk
    end

    normalized.transform_keys(&:to_s).to_json
  end
  private_class_method :resolve_credentials_json
end
