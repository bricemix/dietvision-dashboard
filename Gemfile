source "https://rubygems.org"

gem "rails", "~> 8.0.4"
gem "propshaft"
gem "sqlite3", ">= 2.1"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "jbuilder"

# Auth
gem "bcrypt", "~> 3.1.7"
gem "jwt", "~> 2.9"

# HTTP client (OpenRouter + Mobile Money)
gem "faraday", "~> 2.12"
gem "faraday-retry"

# Paiements internationaux
gem "stripe", "~> 13.0"

# Pagination
gem "pagy", "~> 9.0"

# Charts (admin dashboard)
gem "chartkick"
gem "groupdate"

# CORS (mobile app)
gem "rack-cors"

gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"
gem "bootsnap", require: false
gem "kamal", require: false
gem "thruster", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
