require "test_helper"

class UnsupportedBrowserTest < ActionDispatch::IntegrationTest
  OLD_BROWSER = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.149 Safari/537.36".freeze

  test "the unsupported browser page is styled by a stylesheet the policy allows" do
    get new_session_path, headers: { "User-Agent" => OLD_BROWSER }

    assert_response :not_acceptable
    assert_match(/style-src 'self'/, response.headers["Content-Security-Policy"])
    assert_no_match(/<style|style=/, response.body)
    assert_select "link[rel=stylesheet][href='/406-unsupported-browser.css']"

    get "/406-unsupported-browser.css"
    assert_response :success
    assert_match "text/css", response.media_type
    assert_match "place-items: center", response.body
  end
end
