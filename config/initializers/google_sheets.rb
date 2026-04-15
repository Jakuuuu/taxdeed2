# frozen_string_literal: true

require "google/apis/sheets_v4"
require "googleauth"

# Configuración global de la API de Google
# Aplica a TODAS las llamadas — no poner timeouts individuales en build_service
# (open_timeout_sec= no existe en versiones recientes de google-apis-core)
Google::Apis::RequestOptions.default.retries     = 3
Google::Apis::RequestOptions.default.timeout_sec = 120  # 2 min máximo para recibir respuesta
