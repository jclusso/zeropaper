require "ipaddr"
require "socket"

# Whether a URL points at this machine or the local network, for services
# that count as local, such as Docling. A host is local when it is a
# single-label name (a Docker service like "zeropaper-docling", or
# "localhost") or when every address it resolves to is loopback or in a
# private range.
#
#   LocalNetwork.url?("http://zeropaper-docling:5001")   # => true
#   LocalNetwork.url?("http://192.168.1.20:5001")        # => true
#   LocalNetwork.url?("https://docling.example.com")     # => false
module LocalNetwork
  extend self

  def url?(url)
    uri = URI.parse(url.to_s.strip)
    uri.is_a?(URI::HTTP) && host?(uri.hostname)
  rescue URI::InvalidURIError
    false
  end

  def host?(host)
    host = host.to_s.downcase.delete_suffix(".")
    return false if host.empty?
    return local_address?(host) if ip?(host)
    return true unless host.include?(".")

    addresses = resolve(host)
    addresses.any? && addresses.all? { |address| local_address?(address) }
  end

  private
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
