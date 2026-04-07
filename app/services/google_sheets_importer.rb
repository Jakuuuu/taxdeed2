# frozen_string_literal: true

# GoogleSheetsImporter — Lee filas del Google Sheet de propiedades
#
# Autenticación: Google Service Account (JSON embebido en credentials.yml.enc)
# Scope:         spreadsheets.readonly
# Sheet tab:     "Properties" (fila 1 = encabezado, fila 2+ = datos)
#
class GoogleSheetsImporter
  SHEET_TAB  = "Propeties"  # ⚠️ Nombre exacto de la pestaña en el Sheet (tiene typo intencional)
  DATA_RANGE = "#{SHEET_TAB}!A2:CB" # A2:CB cubre hasta col 79 (CB = index 78)

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
