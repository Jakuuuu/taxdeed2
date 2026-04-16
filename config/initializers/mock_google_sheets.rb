# frozen_string_literal: true

# Simulador de Google Sheets Exclusivo para Development
#
# Propósito: Permite testear el botón "Run Sync Now" y la UI del Sync Dashboard
# en local sin requerir configurar las credenciales reales de Google Cloud.
#
# Mecanismo: Inyecta un override (monkey patch) a GoogleSheetsImporter
# solo cuando estamos en development Y faltan las credenciales reales.
#
# ⚠️ NOTA: Si GOOGLE_APPLICATION_CREDENTIALS apunta a un JSON válido,
#    este mock NO se activa — se usa la API real de Google.
#
if Rails.env.development?
  Rails.application.config.to_prepare do
    if defined?(GoogleSheetsImporter)
      GoogleSheetsImporter.class_eval do
        class << self
          alias_method :_original_fetch_headers_and_rows, :fetch_headers_and_rows

          def fetch_headers_and_rows(sheet_id)
            # Detectar si existen credenciales reales disponibles
            has_json_file = ENV["GOOGLE_APPLICATION_CREDENTIALS"].present? &&
                            File.exist?(ENV["GOOGLE_APPLICATION_CREDENTIALS"].to_s)
            has_inline_json = ENV["GOOGLE_CREDENTIALS_JSON"].present?
            has_rails_creds = Rails.application.credentials.dig(:google_service_account, :private_key).present?
            has_real_sheet  = sheet_id.present? && sheet_id != "mock"

            needs_mock = !has_real_sheet || (!has_json_file && !has_inline_json && !has_rails_creds)

            if needs_mock
              Rails.logger.info "\n"
              Rails.logger.info "=========================================================="
              Rails.logger.info "🤖 [MOCK GOOGLE SHEETS ACTIVADO]"
              Rails.logger.info "No se encontraron credenciales válidas en local."
              Rails.logger.info "Generando datos de prueba para que puedas testear el panel."
              Rails.logger.info "==========================================================\n"

              # Pausa artificial para simular latencia de red
              sleep 1.5

              # ⚠️ IMPORTANTE: Los datos mock deben respetar SheetColumnMap (0-based):
              #   0=State, 1=County, 2=Parcel Number, 6=Auction Date,
              #   7=Market Value, 8=Opening Bid, 9=Assessed Value, etc.
              # Columnas sin datos se rellenan con nil para mantener posiciones correctas.
              {
                headers: [
                  "State", "County", "Parcel Number", "Status", "Notes", "Comments",
                  "Auction Date", "Appraisal (Market Value)", "Min. Bid", "Assessed Value",
                  "Lot Area (acres)", "Lot Area sqft", "Lot Area Home (sqft)"
                ],
                rows: [
                  ["FL", "Miami-Dade", "MOCK-123-#{Time.now.to_i}", nil, nil, nil,
                   1.month.from_now.strftime("%m/%d/%Y"), "$150,000", "$12,000.00", "$120,000",
                   "0.25", "10890", "1500"],
                  ["TX", "Harris", "MOCK-456-#{Time.now.to_i}", nil, nil, nil,
                   2.weeks.from_now.strftime("%m/%d/%Y"), "$85,000", "$5,000.00", "$70,000",
                   "0.15", "6534", "0"]
                ]
              }
            else
              # Credenciales reales disponibles → usar la API de Google
              _original_fetch_headers_and_rows(sheet_id)
            end
          end
        end
      end
    end
  end
end
