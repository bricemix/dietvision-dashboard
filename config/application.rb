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

    # CORS — uniquement pour l'API mobile (pas pour le dashboard admin)
    # origins "*" est interdit sur des endpoints authentifiés (CORS-based CSRF).
    # Les apps mobiles natives n'envoient pas de header Origin → allowlist sans impact.
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        # Domaines web légitimes (admin dashboard, site marketing)
        origins "https://diet-vision.com",
                "https://www.diet-vision.com",
                "https://api.diet-vision.com",
                /\Ahttps:\/\/.*\.diet-vision\.com\z/,
                # Développement local
                "http://localhost:3000",
                "http://localhost:4000",
                "http://127.0.0.1:3000"
        resource "/api/*",
                 headers: :any,
                 methods: %i[get post put patch delete options head],
                 expose: [ "Authorization" ],
                 max_age: 600
      end
    end
  end
end
