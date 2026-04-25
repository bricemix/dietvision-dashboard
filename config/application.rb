require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module DietvisionDashboard
  class Application < Rails::Application
    config.load_defaults 8.0
    config.autoload_lib(ignore: %w[assets tasks])

    # Fuseau horaire Afrique de l'Ouest
    config.time_zone = "Africa/Abidjan"

    # Activer CORS pour les requêtes mobiles
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins "*"
        resource "/api/*", headers: :any, methods: :any, expose: ["Authorization"]
      end
    end
  end
end
