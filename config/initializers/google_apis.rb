# frozen_string_literal: true

# Inicialización de Google APIs para Sheets Sync
# Configura reintentos automáticos para errores de red transitorios

require "google/apis/sheets_v4"
require "googleauth"

# Reintentar hasta 3 veces en errores de servidor de Google
Google::Apis::RequestOptions.default.retries = 3
