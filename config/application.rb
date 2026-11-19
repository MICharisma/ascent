require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Ascent
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0
    config.active_storage.variant_processor = :vips
    config.exceptions_app = ->(env) { ErrorsController.action(:show).call(env) }

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks generators micharisma_seeders])

    config.generators do |generators|
      generators.orm :active_record, primary_key_type: :uuid
    end

    # Add app/views to autoload paths for Phlex components
    # config.autoload_paths << Rails.root.join("app/views")
    # config.autoload_paths << Rails.root.join('lib', 'ext')
    # config.autoload_paths << Rails.root.join('app', 'views', 'components')

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
