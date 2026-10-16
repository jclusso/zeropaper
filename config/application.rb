require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ZeroPaper
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks active_storage])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    config.time_zone = ENV.fetch("TZ", "UTC")
    config.active_job.queue_adapter = :solid_queue

    # Files are only ever served through controllers that check the session.
    config.active_storage.draw_routes = false
    config.active_storage.variant_processor = :vips

    config.assets.paths << Rails.root.join("vendor/pdfjs")

    config.x.ingest_dir = ENV.fetch("INGEST_DIR") { Rails.root.join("storage/ingest").to_s }
    config.x.models_dir = ENV.fetch("MODELS_DIR") { Rails.root.join("storage/models").to_s }
  end
end
