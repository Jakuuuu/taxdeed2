# frozen_string_literal: true

# GoogleSheetsImporter — Lee filas del Google Sheet de propiedades
#
# Autenticación: Google Service Account (JSON embebido en credentials.yml.enc)
# Scope:         spreadsheets.readonly
# Sheet tab:     "Properties" (fila 1 = encabezado, fila 2+ = datos)
#
class GoogleSheetsImporter
  SHEET_TAB  = "Properties"
  DATA_RANGE = "#{SHEET_TAB}!A2:BW" # A2:BW cubre hasta col 75 (BW = index 74)

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

    # Fix para YAML strings que traen escaped newlines literales (\\n)
    if creds_hash[:private_key].is_a?(String)
      creds_hash[:private_key] = creds_hash[:private_key].gsub("\\n", "\n")
    end

    json_key = creds_hash.transform_keys(&:to_s).to_json

    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(json_key),
      scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY
    )
  end
  private_class_method :google_credentials
end
