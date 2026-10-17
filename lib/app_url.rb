require "uri"

# Where people reach the app, for links in emails and printed reset links.
# APP_URL gives the whole address, such as http://nas.local:3000. Without it
# the first APP_HOST is used on the default port. The environment files need
# this at boot, so config/application.rb requires it instead of autoloading.
module AppUrl
  extend self

  # URL options for Rails' url helpers, empty when the address is not known.
  # ssl picks the protocol when only APP_HOST is set.
  def url_options(ssl: false, env: ENV)
    if (url = env["APP_URL"].to_s.strip).present?
      parse(url)
    elsif (host = hosts(env).first)
      { protocol: ssl ? "https" : "http", host: host }
    else
      {}
    end
  end

  def known?(env: ENV)
    url_options(env: env)[:host].present?
  end

  # The hosts listed in APP_HOST.
  def hosts(env = ENV)
    env["APP_HOST"].to_s.split(",").map(&:strip).reject(&:empty?)
  end

  private
    def parse(url)
      uri = URI.parse(url)
      raise URI::InvalidURIError unless uri.is_a?(URI::HTTP) && uri.host.present?

      { protocol: uri.scheme, host: uri.host, port: (uri.port unless uri.port == uri.default_port) }.compact
    rescue URI::InvalidURIError
      raise ArgumentError, "APP_URL must be an address like http://nas.local:3000, not #{url.inspect}"
    end
end
