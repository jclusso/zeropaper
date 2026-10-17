require "test_helper"

class AppUrlTest < ActiveSupport::TestCase
  test "APP_URL gives the protocol, host and port" do
    assert_equal({ protocol: "http", host: "nas.local", port: 3000 }, AppUrl.url_options(env: { "APP_URL" => "http://nas.local:3000" }))
  end

  test "APP_URL leaves out the default port" do
    assert_equal({ protocol: "https", host: "docs.example.com" }, AppUrl.url_options(env: { "APP_URL" => "https://docs.example.com/" }))
  end

  test "APP_URL wins over APP_HOST" do
    options = AppUrl.url_options(env: { "APP_URL" => "http://nas.local:3000", "APP_HOST" => "docs.example.com" })

    assert_equal "nas.local", options[:host]
  end

  test "falls back to the first APP_HOST" do
    assert_equal({ protocol: "http", host: "docs.example.com" }, AppUrl.url_options(env: { "APP_HOST" => " docs.example.com, other.example.com" }))
    assert_equal "https", AppUrl.url_options(ssl: true, env: { "APP_HOST" => "docs.example.com" })[:protocol]
  end

  test "is empty when neither is set" do
    assert_empty AppUrl.url_options(env: { "APP_URL" => " ", "APP_HOST" => "" })
    refute AppUrl.known?(env: {})
    assert AppUrl.known?(env: { "APP_HOST" => "docs.example.com" })
  end

  test "an APP_URL without a scheme is refused" do
    error = assert_raises(ArgumentError) { AppUrl.url_options(env: { "APP_URL" => "nas.local:3000" }) }

    assert_match "http://nas.local:3000", error.message
  end
end
