require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  test "pages are served with an enforced policy that only allows this app" do
    sign_in_as users(:one)

    get documents_path

    assert_response :success
    policy = response.headers["Content-Security-Policy"]
    assert policy, "expected an enforced Content-Security-Policy header"
    assert_nil response.headers["Content-Security-Policy-Report-Only"]
    directives = policy.split(";").to_h { |directive| directive.strip.split(" ", 2) }
    assert_equal "'self'", directives["default-src"]
    assert_match(/\A'self' 'wasm-unsafe-eval' 'nonce-[^']+'\z/, directives["script-src"])
    assert_match(/\A'self' 'nonce-[^']+'\z/, directives["style-src"])
    assert_equal "'self' data: blob:", directives["img-src"]
    assert_equal "'self'", directives["connect-src"]
    assert_equal "'self' blob:", directives["worker-src"]
    assert_equal "'none'", directives["object-src"]
    assert_equal "'none'", directives["frame-ancestors"]
    assert_equal "'self'", directives["base-uri"]
    assert_equal "'self'", directives["form-action"]
  end

  test "every inline script carries the nonce and no element has a style attribute" do
    sign_in_as users(:one)

    get documents_path

    nonce = response.headers["Content-Security-Policy"][/'nonce-([^']+)'/, 1]
    assert_equal nonce, css_select("meta[name='csp-nonce']").sole["content"]
    assert_select "script:not([src])" do |scripts|
      scripts.each { |script| assert_equal nonce, script["nonce"], "inline script without the nonce: #{script.to_html.truncate(120)}" }
    end
    assert_select "[style]", count: 0
  end

  test "a first visit gets a real nonce that stays the same for the session" do
    get new_session_path

    assert_response :success
    nonce = response.headers["Content-Security-Policy"][/'nonce-([^']*)'/, 1]
    assert nonce.present?, "expected a nonce on a first visit"

    get new_session_path
    assert_equal nonce, response.headers["Content-Security-Policy"][/'nonce-([^']*)'/, 1]
  end
end
