# frozen_string_literal: true

# GoogleSheetsImporter — Lee filas del Google Sheet de propiedades
#
# Autenticación: Google Service Account (JSON embebido en credentials.yml.enc)
# Scope:         spreadsheets.readonly
# Sheet tab:     "Propeties" (typo intencional del Sheet original)
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
class GoogleSheetsImporter
  SHEET_TAB  = "Propeties"  # ⚠️ Nombre exacto de la pestaña en el Sheet (typo intencional)
  DATA_RANGE = "#{SHEET_TAB}!A2:CB"
  HEADER_RANGE = "#{SHEET_TAB}!A1:CB1"

  # ── 🛡️ HEADER FAILSAFE ──────────────────────────────────────────────────────
  # Headers OBLIGATORIOS para que el sync proceda.
  # Si alguno falta o fue renombrado → ABORT total + SyncLog.
  REQUIRED_HEADERS = ["State", "County", "Parcel Number"].freeze

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
  def self.validate_headers!(headers)
    normalized_set = headers.map(&:downcase)
    missing = REQUIRED_HEADERS.reject { |req| normalized_set.include?(req.downcase) }

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

  # Carga las credenciales del Service Account desde Rails credentials
  def self.google_credentials
    creds_hash = Rails.application.credentials.google_service_account
    raise "Missing google_service_account credentials" if creds_hash.blank?

    # Reconstrucción a prueba de fallos de la RSA Private Key
    if creds_hash[:private_key].present?
      raw_key = creds_hash[:private_key].to_s
      base64_only = raw_key.gsub(/-----BEGIN PRIVATE KEY-----/, "")
                           .gsub(/-----END PRIVATE KEY-----/, "")
                           .gsub(/\\n|\\r/, "")
                           .gsub(/\s+/, "")

      pem_lines = base64_only.scan(/.{1,64}/)
      creds_hash[:private_key] = ["-----BEGIN PRIVATE KEY-----", *pem_lines, "-----END PRIVATE KEY-----\n"].join("\n")
    end

    json_key = creds_hash.transform_keys(&:to_s).to_json

    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(json_key),
      scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY
    )
  end
  private_class_method :google_credentials
end
