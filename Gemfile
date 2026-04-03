source "https://rubygems.org"

gem "rails", "~> 7.2.3", ">= 7.2.3.1"
gem "sprockets-rails"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false

# ── Auth ──────────────────────────────────────────────────────────────────────
gem "devise"

# ── Pagos (instalado; PaymentService en MOCK_MODE hasta activar Stripe real) ──
gem "stripe"

# ── Background Jobs ───────────────────────────────────────────────────────────
gem "redis", ">= 4.0.1"
gem "sidekiq"
gem "sidekiq-cron"

# ── Google Sheets (se activa en Módulo 2 — Parcels/Sync) ─────────────────────
gem "google-apis-sheets_v4"
gem "googleauth"

# ── Pagination ────────────────────────────────────────────────────────────────
gem "kaminari"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "dotenv-rails"
end

group :development do
  gem "web-console"
  gem "foreman", require: false
end
