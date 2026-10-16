require "ipaddr"
require "socket"

# Whether a URL points at this machine or the local network, for services
# that count as local, such as Docling. A host is local when every address
# it resolves to is loopback or in a private range.
# Every name is resolved, single-label ones too (a Docker service like
# "zeropaper-docling", or "localhost"), so a number that resolves to a
# public address, like "134744072", is refused.
#
#   LocalNetwork.url?("http://zeropaper-docling:5001")   # => true
#   LocalNetwork.url?("http://192.168.1.20:5001")        # => true
#   LocalNetwork.url?("https://docling.example.com")     # => false
module LocalNetwork
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

  # Whether the URL is known to point elsewhere: it is not an HTTP URL, or
  # its host resolves to an address that is not local. A name that does not
  # resolve yet, such as a container that is still starting, is not.
  def elsewhere?(url)
    uri = URI.parse(url.to_s.strip)
    return true unless uri.is_a?(URI::HTTP)

    host = normalize(uri.hostname)
    host.empty? || all_addresses(host).any? { |address| !local_address?(address) }
  rescue URI::InvalidURIError
    true
  end

  private
    def host_addresses(host)
      host = normalize(host)
      return if host.empty?

      addresses = all_addresses(host)
      addresses if addresses.any? && addresses.all? { |address| local_address?(address) }
    end

    def normalize(host)
      host.to_s.downcase.delete_suffix(".")
    end

    def all_addresses(host)
      ip?(host) ? [ host ] : resolve(host)
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
      ip.loopback? || ip.private?
    rescue IPAddr::InvalidAddressError
      false
    end

    def resolve(host)
      Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
    rescue SocketError
      []
    end
end
