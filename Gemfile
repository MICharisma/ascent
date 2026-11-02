source "https://rubygems.org"
ruby "4.0.9"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1", ">= 8.1.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
gem "activerecord-postgis-adapter", "~> 11.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
# Use Phlex for view components [https://github.com/phlex-rb/phlex]
gem "phlex", "~> 2.4"
gem "phlex-rails", "~> 2.4"
# Lucide icons as Phlex components [https://github.com/AliOsm/phlex-icons]
gem "phlex-icons-lucide"
gem "literal"
gem "superform"

# Use Devise for authentication [https://github.com/heartcombo/devise]
gem "devise"
# Sign in with Google through Devise; the CSRF gem makes OmniAuth accept only POST requests with a token
gem "omniauth-google-oauth2", "~> 1.2"
gem "omniauth-rails_csrf_protection", "~> 2.0"

# Authorization [https://github.com/palkan/action_policy]
gem "action_policy"

# Pagination [https://github.com/ddnexus/pagy]
gem "pagy"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

gem "image_processing", "~> 2.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  gem "rspec-rails"
  gem "shoulda"
  gem "faker"
  gem "rails-controller-testing"

  # gem 'claude-on-rails'

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

gem "factory_bot_rails"

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"

  # Code coverage reporting [https://github.com/simplecov-ruby/simplecov]
  gem "simplecov", require: false
  gem "simplecov-html", require: false
end

gem "ruby-lsp", "~> 0.26.11"

gem "csv", "~> 3.3"

# Database views as versioned migrations, for the counted mountain ratings [https://github.com/scenic-views/scenic]
gem "scenic", "~> 1.9"
# Median and percentile calculations in ActiveRecord, for results statistics [https://github.com/ankane/active_median]
gem "active_median", "~> 1.0"
# GeoJSON reading for TIGER/Line boundary imports [https://github.com/rgeo/rgeo-geojson]
gem "rgeo-geojson", "~> 2.2"

gem "ahoy_matey", "~> 5.5"

gem "postshiba", git: "https://github.com/postshiba/postshiba-ruby.git"
