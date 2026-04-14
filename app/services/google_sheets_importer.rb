# frozen_string_literal: true

# GoogleSheetsImporter — Lee filas del Google Sheet de propiedades
#
# Autenticación: Google Service Account (JSON embebido en credentials.yml.enc)
# Scope:         spreadsheets.readonly
# Sheet tab:     "Properties" (fila 1 = encabezado, fila 2+ = datos)
#
# Timeouts:
#   - open_timeout_sec: 30s  — máximo para establecer conexión con Google
#   - timeout_sec:      120s — máximo para recibir la respuesta completa
#   Esto evita que el job quede colgado si Google no responde,
#   previniendo que Render mate el proceso por inactividad.
#
# 🛡️ MAPEO RESILIENTE: fetch_headers_and_rows normaliza cabeceras con .strip
#    para eliminar espacios invisibles (NBSP, trailing spaces, tabs) que podrían
#    romper el mapeo si se migrara a lookup por nombre de columna.
#
class GoogleSheetsImporter
  SHEET_TAB  = "Propeties"  # ⚠️ Nombre exacto de la pestaña en el Sheet (tiene typo intencional)
  DATA_RANGE = "#{SHEET_TAB}!A2:CB" # A2:CB cubre hasta col 79 (CB = index 78)
  HEADER_RANGE = "#{SHEET_TAB}!A1:CB1" # Fila 1: cabeceras

  # Retorna solo filas de datos (sin cabecera) — compatibilidad con el flujo actual.
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
  # Las cabeceras se normalizan con .strip para eliminar caracteres invisibles.
  # Útil para validación de integridad o futura migración a mapeo por nombre.
  def self.fetch_headers_and_rows(sheet_id)
    service = build_service

    # Fetch cabeceras (fila 1)
    header_response = service.get_spreadsheet_values(sheet_id, HEADER_RANGE)
    raw_headers = header_response.values&.first || []
    # 🛡️ Normalizar: eliminar NBSP, trailing spaces, tabs, BOM, etc.
    normalized_headers = raw_headers.map { |h| h.to_s.strip.gsub(/\u00A0/, " ").strip }

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

  def self.build_service
    service = Google::Apis::SheetsV4::SheetsService.new
    service.authorization = google_credentials

    # ── TIMEOUTS: Prevenir hang indefinido en Render ──────────────────────
    # Si Google Sheets no responde dentro de estos límites, el job falla
    # limpiamente y Sidekiq reintenta con backoff (retry_on en SyncSheetJob).
    service.request_options.open_timeout_sec = 30   # Conexión TCP
    service.request_options.timeout_sec      = 120  # Respuesta completa

    service
  end
  private_class_method :build_service

  # Carga las credenciales del Service Account desde Rails credentials
  def self.google_credentials
    creds_hash = Rails.application.credentials.google_service_account
    raise "Missing google_service_account credentials" if creds_hash.blank?

    # Reconstrucción a prueba de fallos de la RSA Private Key (evita 'Neither PUB key nor PRIV key')
    if creds_hash[:private_key].present?
      raw_key = creds_hash[:private_key].to_s
      # 1. Extraer solo el contenido base64 ignorando basura, saltos de línea y cabeceras
      base64_only = raw_key.gsub(/-----BEGIN PRIVATE KEY-----/, '')
                           .gsub(/-----END PRIVATE KEY-----/, '')
                           .gsub(/\\n|\\r/, '') # Eliminar saltos literales representados como texto
                           .gsub(/\s+/, '')     # Eliminar saltos reales y espacios

      # 2. Partir en trozos de 64 caracteres (estándar PEM)
      pem_lines = base64_only.scan(/.{1,64}/)

      # 3. Reconstruir con los saltos de línea perfectos
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
