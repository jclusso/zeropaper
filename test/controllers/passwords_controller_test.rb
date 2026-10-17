require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  include CableDisconnects
  include EnvHelpers

  setup { @user = User.take }

  test "the reset pages use the sign-in layout, not the app shell" do
    sign_out
    with_mail_from { get new_password_path }

    assert_response :success
    assert_select "aside", count: 0
    assert_select "input[type=email][placeholder]"
  end

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "create" do
    with_mail_from { post passwords_path, params: { email_address: @user.email_address } }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "create for an unknown user redirects but sends no mail" do
    with_mail_from { post passwords_path, params: { email_address: "missing-user@example.com" } }
    assert_enqueued_emails 0
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "without mail the page says so and shows the reset command instead of a form" do
    with_env("MAIL_FROM" => nil) { get new_password_path }

    assert_response :success
    assert_select "form[action=?]", passwords_path, count: 0
    assert_select "p", /Email is not set up/
    assert_select "pre", /bin\/rails users:reset_password EMAIL=/
    assert_no_match(/We will email you/, response.body)
  end

  test "in production without APP_URL or APP_HOST the page shows the reset command" do
    Rails.stubs(:env).returns(ActiveSupport::EnvironmentInquirer.new("production"))
    with_mail_from do
      with_env("APP_URL" => nil, "APP_HOST" => nil) { get new_password_path }
    end

    assert_response :success
    assert_select "form[action=?]", passwords_path, count: 0
    assert_select "pre", /bin\/rails users:reset_password EMAIL=/
  end

  test "without mail a request sends nothing and claims nothing was sent" do
    with_env("MAIL_FROM" => nil) do
      post passwords_path, params: { email_address: @user.email_address }
      assert_redirected_to new_password_path
      follow_redirect!
    end

    assert_enqueued_emails 0
    assert_no_match(/instructions sent/, response.body)
    assert_select "p", /Email is not set up/
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with invalid password reset token" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_notice "reset link is invalid"
  end

  test "update" do
    assert_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token), params: { password: "a much longer password", password_confirmation: "a much longer password" }
      assert_redirected_to new_session_path
    end

    follow_redirect!
    assert_notice "Password has been reset"
  end

  test "a reset removes the user's passkeys" do
    @user.passkeys.create!(external_id: "abc", public_key: "key", name: "Borrowed laptop")

    put password_path(@user.password_reset_token), params: { password: "a much longer password", password_confirmation: "a much longer password" }

    assert_redirected_to new_session_path
    assert_empty @user.passkeys.reload
  end

  test "a reset closes every open connection" do
    sessions = Array.new(2) { @user.sessions.create! }

    put password_path(@user.password_reset_token), params: { password: "a much longer password", password_confirmation: "a much longer password" }

    sessions.each { |session| assert_equal 1, cable_disconnects(session) }
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "no", password_confirmation: "match" }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_notice "Passwords did not match"
  end

  private
    def assert_notice(text)
      assert_select "div", /#{text}/
    end
end
