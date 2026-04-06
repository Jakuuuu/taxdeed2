# frozen_string_literal: true

# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

  # ── RLS bypass para jobs en background ──────────────────────────────────
  # Los workers de Sidekiq no tienen un current_user autenticado.
  # Usamos el sentinel '0' para que las políticas RLS les permitan leer
  # todas las filas (necesario para SyncSheetJob, ReportGenerationJob, etc.)
  config.server_middleware do |chain|
    chain.add Class.new do
      def call(worker, job, queue)
        ActiveRecord::Base.connection.execute(
          "SELECT set_config('app_user.id', '0', true)"
        )
        yield
      rescue ActiveRecord::StatementInvalid
        yield # Si RLS no está migrado aún, no interrumpir el job
      end
    end
  end

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