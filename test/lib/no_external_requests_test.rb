require "test_helper"

# The privacy tests lean on assert_no_external_requests, so it has to fail
# whenever a request leaves this machine, stubbed or not.
class NoExternalRequestsTest < ActiveSupport::TestCase
  test "passes when nothing was requested or only this machine was" do
    stub_request(:get, "http://localhost:5001/health")
    HTTPX.get("http://localhost:5001/health")

    assert_no_external_requests
  end

  test "fails on a stubbed request to a hosted provider" do
    stub_request(:post, "https://api.openai.com/v1/responses")
    HTTPX.post("https://api.openai.com/v1/responses", json: {})

    error = assert_raises(Minitest::Assertion) { assert_no_external_requests }
    assert_match "api.openai.com", error.message
  end

  test "fails on a request that was refused" do
    assert_raises(VCR::Errors::UnhandledHTTPRequestError) { HTTPX.get("https://docling.example.com/v1/convert/file") }

    error = assert_raises(Minitest::Assertion) { assert_no_external_requests }
    assert_match "docling.example.com", error.message
  end
end
