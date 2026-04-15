# frozen_string_literal: true

# Configuración global de la API de Google
# NOTA: google-apis-core en Render no expone timeout_sec= ni open_timeout_sec=
# como setters en RequestOptions.default. Solo configuramos retries que sí existe.
begin
  Google::Apis::RequestOptions.default.retries = 3
rescue NoMethodError
  # Versión antigua de google-apis-core — ignorar
end
