# The Docker service names tests use for Docling resolve to a container
# address, as they would inside the Compose network.
module LocalHostnames
  HOSTS = { "docling" => [ "172.18.0.4" ], "zeropaper-docling" => [ "172.18.0.4" ] }.freeze

  private
    def resolve(host)
      HOSTS.fetch(host) { super }
    end
end

LocalNetwork.singleton_class.prepend(LocalHostnames)
