# Be sure to restart your server when you modify this file.
#
# Content Security Policy (CSP) — TaxDeed Lion
# Allowlist estricto para los dominios de terceros que realmente usamos.
#
# MODO ACTUAL: report_only = true → solo reporta violaciones, no bloquea.
# Para activar el modo enforce: cambiar a report_only = false
# Una vez verificado que no hay violaciones en los logs de Render.

Rails.application.configure do
  config.content_security_policy do |policy|
    # Fuentes por defecto: solo el propio origen
    policy.default_src :self

    # Scripts: propio dominio + Google Maps JS + Stripe.js + Leaflet CDN
    # 'unsafe-inline' NO necesario gracias a nonces
    policy.script_src  :self,
                       "https://maps.googleapis.com",
                       "https://maps.gstatic.com",
                       "https://js.stripe.com",
                       "https://unpkg.com"

    # Estilos: propio dominio + Google Fonts + Leaflet CDN
    policy.style_src   :self,
                       "https://fonts.googleapis.com",
                       "https://unpkg.com"

    # Fuentes: propio dominio + Google Fonts CDN
    policy.font_src    :self,
                       "https://fonts.gstatic.com",
                       :data

    # Imágenes: propio dominio + Google Maps tiles + OpenStreetMap tiles + data URIs + GCS
    policy.img_src     :self,
                       "https://maps.googleapis.com",
                       "https://maps.gstatic.com",
                       "https://streetviewpixels-pa.googleapis.com",
                       "https://storage.googleapis.com",
                       "https://*.tile.openstreetmap.org",
                       :data,
                       :blob

    # Frames: Google Maps embed + Stripe Checkout iframes
    policy.frame_src   "https://www.google.com",
                       "https://js.stripe.com",
                       "https://hooks.stripe.com"

    # Conexiones AJAX / fetch / WebSocket: propio dominio + Google APIs + Stripe
    policy.connect_src :self,
                       "https://maps.googleapis.com",
                       "https://api.stripe.com"

    # Objetos/plugins: ninguno (sin Flash, sin PDFs embebidos)
    policy.object_src  :none

    # Evitar clickjacking (frame-ancestors vacío = nadie puede embeberte)
    policy.frame_ancestors :none

    # No permitir upgrade implícito a mixed content
    policy.base_uri    :self
  end

  # Nonces para <script> y <style> inline compatibles con Turbo/Importmap
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src style-src]

  # MODO REPORT-ONLY: reporta sin bloquear. Cambiar a false para enforce.
  # Monitorear violaciones en: Render logs o agregar report_uri a un endpoint.
  config.content_security_policy_report_only = true
end
