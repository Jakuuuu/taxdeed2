namespace :creds do
  desc "Inject new Google Cloud credentials for sync-bot"
  task inject: :environment do
    json_path = 'C:/Users/danie/Downloads/lion-legacy-lands-db-e1e6ce5e1a45.json'
    json = JSON.parse(File.read(json_path))
    hash = YAML.load(Rails.application.credentials.read.to_s) || {}
    hash[:google_service_account] = json
    Rails.application.encrypted('config/credentials.yml.enc', key_path: 'config/master.key').write(hash.to_yaml)
    puts 'EXITO_CREDENCIALES_NUEVAS_Y_VALIDAS'
  end
end
