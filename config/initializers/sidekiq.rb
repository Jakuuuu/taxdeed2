# frozen_string_literal: true

# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

  # Cargar schedules de sidekiq-cron al iniciar el server
  config.on(:startup) do
    schedule_file = Rails.root.join("config", "sidekiq.yml")
    if File.exist?(schedule_file)
      schedule = YAML.load(ERB.new(File.read(schedule_file)).result)
      cron_jobs = schedule[:cron] || schedule["cron"] || {}
      Sidekiq::Cron::Job.load_from_hash(cron_jobs) if cron_jobs.any?
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end