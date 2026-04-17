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
# 🚀 MEMORY-SAFE (v3): Intercepta TANTO el método legacy (fetch_headers_and_rows)
#    como el streaming (fetch_rows_in_chunks) para compatibilidad total.
#
if Rails.env.development?
  Rails.application.config.to_prepare do
    if defined?(GoogleSheetsImporter)
      GoogleSheetsImporter.class_eval do
        class << self
          alias_method :_original_fetch_headers_and_rows, :fetch_headers_and_rows
          alias_method :_original_fetch_rows_in_chunks, :fetch_rows_in_chunks

          # ── Detectar si necesitamos mock ──────────────────────────────────
          def _needs_mock?(sheet_id)
            has_json_file = ENV["GOOGLE_APPLICATION_CREDENTIALS"].present? &&
                            File.exist?(ENV["GOOGLE_APPLICATION_CREDENTIALS"].to_s)
            has_inline_json = ENV["GOOGLE_CREDENTIALS_JSON"].present?
            has_rails_creds = Rails.application.credentials.dig(:google_service_account, :private_key).present?
            has_real_sheet  = sheet_id.present? && sheet_id != "mock"

            !has_real_sheet || (!has_json_file && !has_inline_json && !has_rails_creds)
          end

          # ── Generar filas mock ────────────────────────────────────────────
          # ⚠️ IMPORTANTE: Los datos mock deben respetar SheetColumnMap (0-based):
          #   0=State, 1=County, 2=Parcel Number, 6=Auction Date,
          #   7=Market Value, 8=Opening Bid, 9=Assessed Value, etc.
          # Columnas sin datos se rellenan con nil para mantener posiciones correctas.
          def _mock_rows
            [
              ["FL", "Miami-Dade", "MOCK-123-#{Time.now.to_i}", nil, nil, nil,
               1.month.from_now.strftime("%m/%d/%Y"), "$150,000", "$12,000.00", "$120,000",
               "0.25", "10890", "1500"],
              ["TX", "Harris", "MOCK-456-#{Time.now.to_i}", nil, nil, nil,
               2.weeks.from_now.strftime("%m/%d/%Y"), "$85,000", "$5,000.00", "$70,000",
               "0.15", "6534", "0"],
              ["FL", "Duval", "MOCK-789-#{Time.now.to_i}", nil, nil, nil,
               3.weeks.from_now.strftime("%m/%d/%Y"), "$200,000", "$18,500.00", "$175,000",
               "0.50", "21780", "2200"],
              ["TX", "Dallas", "MOCK-012-#{Time.now.to_i}", nil, nil, nil,
               1.month.from_now.strftime("%m/%d/%Y"), "$65,000", "$3,200.00", "$55,000",
               "0.10", "4356", "0"]
            ]
          end

          def _mock_headers
            [
              "State", "County", "Parcel Number", "Status", "Notes", "Comments",
              "Auction Date", "Appraisal (Market Value)", "Min. Bid", "Assessed Value",
              "Lot Area (acres)", "Lot Area sqft", "Lot Area Home (sqft)"
            ]
          end

          def _log_mock_activation!
            Rails.logger.info "\n"
            Rails.logger.info "=========================================================="
            Rails.logger.info "🤖 [MOCK GOOGLE SHEETS ACTIVADO]"
            Rails.logger.info "No se encontraron credenciales válidas en local."
            Rails.logger.info "Generando datos de prueba para que puedas testear el panel."
            Rails.logger.info "==========================================================\n"
          end

          # ═══════════════════════════════════════════════════════════════════
          # 🚀 STREAMING MOCK — fetch_rows_in_chunks
          # Yield las filas mock en un solo chunk, exactamente como lo haría
          # la API real. El caller (SyncSheetJob) no nota la diferencia.
          # ═══════════════════════════════════════════════════════════════════
          def fetch_rows_in_chunks(sheet_id, chunk_size: CHUNK_SIZE, &block)
            if _needs_mock?(sheet_id)
              _log_mock_activation!
              sleep 1.5 # Simular latencia de red

              # Validar headers (igual que el método real)
              validate_headers!(_mock_headers)

              # Yield todas las filas mock como un solo chunk
              mock_rows = _mock_rows
              yield mock_rows, 0

              Rails.logger.info "[GoogleSheetsImporter] ✅ Mock streaming completo: #{mock_rows.size} filas en 1 chunk"
              { headers: _mock_headers, total_rows: mock_rows.size, total_chunks: 1 }
            else
              # Credenciales reales disponibles → usar la API de Google
              _original_fetch_rows_in_chunks(sheet_id, chunk_size: chunk_size, &block)
            end
          end

          # ═══════════════════════════════════════════════════════════════════
          # LEGACY MOCK — fetch_headers_and_rows (deprecado pero funcional)
          # ═══════════════════════════════════════════════════════════════════
          def fetch_headers_and_rows(sheet_id)
            if _needs_mock?(sheet_id)
              _log_mock_activation!
              sleep 1.5

              { headers: _mock_headers, rows: _mock_rows }
            else
              _original_fetch_headers_and_rows(sheet_id)
            end
          end
        end
      end
    end
  end
end
