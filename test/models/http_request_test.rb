require "test_helper"

class HttpRequestTest < ActiveSupport::TestCase
  test "an unreachable address is retried over IPv4" do
    stub_request(:get, "https://api.example.test/v1/models")
      .to_raise(Errno::EHOSTUNREACH.new("connect(2) for [2606:4700:7::f3]:443"))
      .then.to_return(status: 200, body: "{}")

    response = HttpRequest.get("https://api.example.test/v1/models")

    assert_equal 200, response.status
    assert_requested :get, "https://api.example.test/v1/models", times: 2
  end

  test "other failures are not retried" do
    stub_request(:get, "https://api.example.test/v1/models").to_raise(Errno::ECONNREFUSED)

    response = HttpRequest.get("https://api.example.test/v1/models")

    assert_kind_of HTTPX::ErrorResponse, response
    assert_requested :get, "https://api.example.test/v1/models", times: 1
  end

  test "a provider check survives a network without IPv6" do
    stub_request(:get, "https://api.openai.com/v1/models")
      .to_raise(Errno::EHOSTUNREACH).then.to_return(status: 200, body: '{"data":[]}')

    assert AIProvider.new(kind: "openai", api_key: TestKeys::OPENAI).verify.ok?
  end
end
