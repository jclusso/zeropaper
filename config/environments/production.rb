require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Thruster serves files from disk, byte ranges included, so Puma threads
  # are not held for the length of a download.
  config.action_dispatch.x_sendfile_header = "X-Sendfile"

  # Set ASSUME_SSL when a reverse proxy terminates TLS in front of the app.
  config.assume_ssl = ENV["ASSUME_SSL"] == "true"

  # Set FORCE_SSL to redirect to HTTPS, send Strict-Transport-Security, and use secure cookies.
  config.force_ssl = ENV["FORCE_SSL"] == "true"
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue


  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Links in emails and printed reset links point at APP_URL, or at the first
  # APP_HOST when APP_URL is unset. Without either, mail counts as off.
  config.action_mailer.default_url_options = AppUrl.url_options(ssl: config.force_ssl || config.assume_ssl)
  Rails.application.routes.default_url_options = config.action_mailer.default_url_options

  # Specify outgoing SMTP server, with the login passed in as environment variables.
  # config.action_mailer.smtp_settings = {
  #   user_name: ENV["SMTP_USERNAME"],
  #   password: ENV["SMTP_PASSWORD"],
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # When APP_HOST is set, refuse requests for any other host. The container
  # health check calls /up on localhost, so it is exempt.
  if AppUrl.hosts.any?
    config.hosts = AppUrl.hosts
    config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
  end
end
