# frozen_string_literal: true

# Simulador de Google Sheets Exclusivo para Development
#
# Propósito: Permite testear el botón "Run Sync Now" y la UI del Sync Dashboard
# en local sin requerir configurar las credenciales reales de Google Cloud.
# 
# Mecanismo: Inyecta un override (monkey patch) a GoogleSheetsImporter 
# solo cuando estamos en development y la hoja de sheet (sheet_id) es nula.
if Rails.env.development?
  Rails.application.config.to_prepare do
    if defined?(GoogleSheetsImporter)
      GoogleSheetsImporter.class_eval do
        class << self
          alias_method :_original_fetch_headers_and_rows, :fetch_headers_and_rows

          def fetch_headers_and_rows(sheet_id)
            # Detectar si faltan credenciales (para activar el simulador)
            needs_mock = sheet_id.blank? || sheet_id == "mock" || Rails.application.credentials.dig(:google_sheets, :sheet_id).blank?
            
            if needs_mock
              Rails.logger.info "\n"
              Rails.logger.info "=========================================================="
              Rails.logger.info "🤖 [MOCK GOOGLE SHEETS ACTIVADO]"
              Rails.logger.info "No se encontraron credenciales válidas en local."
              Rails.logger.info "Generando datos de prueba para que puedas testear el panel."
              Rails.logger.info "==========================================================\n"
              
              # Pausa artificial para simular latencia de red
              sleep 1.5 

              {
                headers: [
                  "State", "County", "Parcel Number", "Tax Amount", 
                  "Auction Date", "Opening Bid", "Assessed Value"
                ],
                rows: [
                  ["FL", "Miami-Dade", "MOCK-123-#{Time.now.to_i}", "$10,500.00", 1.month.from_now.strftime("%m/%d/%Y"), "$12,000.00", "$150,000"],
                  ["TX", "Harris", "MOCK-456-#{Time.now.to_i}", "$4,200.00", 2.weeks.from_now.strftime("%m/%d/%Y"), "$5,000.00", "$85,000"]
                ]
              }
            else
              # Si por algún motivo tienes credenciales, usa la función real
              _original_fetch_headers_and_rows(sheet_id)
            end
          end
        end
      end
    end
  end
end
