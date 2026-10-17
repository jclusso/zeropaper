require "socket"

# Outgoing HTTP for provider checks, model lists and Docling. Networks that
# hand out a local-only IPv6 address make HTTPX try IPv6 first and fail with
# "No route to host"; when that happens the request is retried over IPv4.
# A request given addresses connects only to those, without resolving the
# host again.
module HttpRequest
  UNREACHABLE = [ Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::EADDRNOTAVAIL ].freeze

  extend self

  def get(url, headers: {}, read_timeout: 15)
    perform(read_timeout) { |client| client.get(url, headers: headers) }
  end

  def post(url, form:, read_timeout: 15, addresses: nil)
    pinned = { URI.parse(url).host => addresses } if addresses
    perform(read_timeout, pinned) { |client| client.post(url, form: form) }
  end

  private
    def perform(read_timeout, addresses = nil)
      response = yield client(read_timeout, addresses)
      return response unless unreachable?(response)

      ipv4 = addresses&.transform_values { |list| list.select { |address| IPAddr.new(address).ipv4? } }
      return response if ipv4&.values&.any?(&:empty?)

      yield client(read_timeout, ipv4, ip_families: [ Socket::AF_INET ])
    end

    def client(read_timeout, addresses, **options)
      options[:addresses] = addresses if addresses
      HTTPX.with(timeout: { connect_timeout: 5, read_timeout: read_timeout }, **options)
    end

    def unreachable?(response)
      return false unless response.is_a?(HTTPX::ErrorResponse)

      error = response.error
      error = error.cause while error.respond_to?(:cause) && error.cause && !UNREACHABLE.any? { |kind| error.is_a?(kind) }
      UNREACHABLE.any? { |kind| error.is_a?(kind) } || response.error.message.match?(/no route to host|network is unreachable/i)
    end
end
