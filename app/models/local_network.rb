require "ipaddr"
require "socket"

# Whether a URL points at this machine or the local network, for services
# that count as local, such as Docling. A host is local when every address
# it resolves to is loopback, in a private range, or in Tailscale's range.
# Every name is resolved, single-label ones too (a Docker service like
# "zeropaper-docling", or "localhost"), so a number that resolves to a
# public address, like "134744072", is refused.
#
#   LocalNetwork.url?("http://zeropaper-docling:5001")   # => true
#   LocalNetwork.url?("http://192.168.1.20:5001")        # => true
#   LocalNetwork.url?("https://docling.example.com")     # => false
module LocalNetwork
  # Tailscale hands out addresses from the carrier-grade NAT range.
  SHARED_RANGES = [ IPAddr.new("100.64.0.0/10") ].freeze

  extend self

  def url?(url)
    addresses(url).present?
  end

  # The addresses the URL's host resolves to when all of them are local,
  # for pinning a request to them; nil otherwise.
  def addresses(url)
    uri = URI.parse(url.to_s.strip)
    host_addresses(uri.hostname) if uri.is_a?(URI::HTTP)
  rescue URI::InvalidURIError
    nil
  end

  def host?(host)
    host_addresses(host).present?
  end

  private
    def host_addresses(host)
      host = host.to_s.downcase.delete_suffix(".")
      return if host.empty?

      addresses = ip?(host) ? [ host ] : resolve(host)
      addresses if addresses.any? && addresses.all? { |address| local_address?(address) }
    end

    def ip?(host)
      IPAddr.new(host)
      true
    rescue IPAddr::InvalidAddressError
      false
    end

    def local_address?(address)
      ip = IPAddr.new(address)
      ip = ip.native if ip.ipv4_mapped?
      ip.loopback? || ip.private? || SHARED_RANGES.any? { |range| range.include?(ip) }
    rescue IPAddr::InvalidAddressError
      false
    end

    def resolve(host)
      Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
    rescue SocketError
      []
    end
end
