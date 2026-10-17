require "test_helper"
require "webauthn/fake_client"

class PasskeysControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  include EnvHelpers

  setup do
    @user = users(:two)
    @client = WebAuthn::FakeClient.new("http://www.example.com")
    sign_in_as @user
  end

  test "adding a passkey needs the current password" do
    post passkeys_challenge_path, params: {}, as: :json

    assert_response :unprocessable_entity
    assert_equal "Enter your current password to add a passkey.", response.parsed_body["error"]
    assert_no_difference -> { @user.passkeys.count } do
      post passkeys_path, params: { credential: fake_credential(random_challenge), name: "Borrowed laptop" }, as: :json
    end
    assert_response :unprocessable_entity
  end

  test "a wrong current password does not start registration" do
    post passkeys_challenge_path, params: { current_password: "wrong" }, as: :json

    assert_response :unprocessable_entity
    assert_equal "Your current password is incorrect.", response.parsed_body["error"]
    assert_nil response.parsed_body["challenge"]
  end

  test "a passkey is added with the current password and the owner is emailed" do
    post passkeys_challenge_path, params: { current_password: "password" }, as: :json
    assert_response :success

    assert_difference -> { @user.passkeys.count } do
      assert_enqueued_email_with PasskeysMailer, :added, args: [ @user, "MacBook" ] do
        with_mail_from do
          post passkeys_path, params: { credential: fake_credential(response.parsed_body["challenge"]), name: "MacBook" }, as: :json
        end
      end
    end
    assert_equal({ "location" => profile_path }, response.parsed_body)
  end

  test "no email is sent without MAIL_FROM, even with SMTP set up" do
    ApplicationMailer.stubs(:delivery_method).returns(:smtp)
    ApplicationMailer.stubs(:smtp_settings).returns(address: "smtp.example.com", port: 587)
    post passkeys_challenge_path, params: { current_password: "password" }, as: :json

    assert_difference -> { @user.passkeys.count } do
      assert_no_enqueued_emails do
        with_env("MAIL_FROM" => nil) do
          post passkeys_path, params: { credential: fake_credential(response.parsed_body["challenge"]), name: "MacBook" }, as: :json
        end
      end
    end
  end

  test "a registration challenge older than five minutes is refused and dropped" do
    post passkeys_challenge_path, params: { current_password: "password" }, as: :json
    credential = fake_credential(response.parsed_body["challenge"])

    travel 6.minutes do
      assert_no_difference -> { @user.passkeys.count } do
        post passkeys_path, params: { credential: credential, name: "MacBook" }, as: :json
      end
      assert_response :unprocessable_entity
      assert_equal "Start again.", response.parsed_body["error"]
    end

    post passkeys_path, params: { credential: credential, name: "MacBook" }, as: :json
    assert_response :unprocessable_entity
    assert_equal 0, @user.passkeys.count
  end

  test "a registration challenge works only once" do
    post passkeys_challenge_path, params: { current_password: "password" }, as: :json
    credential = fake_credential(response.parsed_body["challenge"])

    post passkeys_path, params: { credential: credential, name: "MacBook" }, as: :json
    assert_response :success

    assert_no_difference -> { @user.passkeys.count } do
      post passkeys_path, params: { credential: credential, name: "MacBook again" }, as: :json
    end
    assert_response :unprocessable_entity
    assert_equal "Start again.", response.parsed_body["error"]
  end

  test "signing out drops a pending registration challenge" do
    post passkeys_challenge_path, params: { current_password: "password" }, as: :json
    credential = fake_credential(response.parsed_body["challenge"])
    delete session_path
    sign_in_as @user

    assert_no_difference -> { @user.passkeys.count } do
      post passkeys_path, params: { credential: credential, name: "MacBook" }, as: :json
    end
    assert_response :unprocessable_entity
  end

  test "signing out drops a pending sign-in challenge" do
    post passkeys_challenge_path, params: { current_password: "password" }, as: :json
    post passkeys_path, params: { credential: fake_credential(response.parsed_body["challenge"]), name: "MacBook" }, as: :json
    post sessions_passkey_challenge_path, as: :json
    assertion = @client.get(challenge: response.parsed_body["challenge"], rp_id: "www.example.com", user_verified: true)
    delete session_path

    assert_no_difference -> { Session.count } do
      post sessions_passkey_path, params: { credential: assertion }, as: :json
    end
    assert_response :unprocessable_entity
  end

  test "signing in with a passkey" do
    post passkeys_challenge_path, params: { current_password: "password" }, as: :json
    post passkeys_path, params: { credential: fake_credential(response.parsed_body["challenge"]), name: "MacBook" }, as: :json
    sign_out

    post sessions_passkey_challenge_path, as: :json
    assertion = @client.get(challenge: response.parsed_body["challenge"], rp_id: "www.example.com", user_verified: true)

    assert_difference -> { @user.sessions.count } do
      post sessions_passkey_path, params: { credential: assertion }, as: :json
    end
    assert_response :success
    assert_equal root_url, response.parsed_body["location"]
    assert @user.passkeys.last.last_used_at
  end

  test "a passkey the app does not know does not sign in" do
    fake_credential(random_challenge)
    post sessions_passkey_challenge_path, as: :json
    assertion = @client.get(challenge: response.parsed_body["challenge"], rp_id: "www.example.com", user_verified: true)

    assert_no_difference -> { Session.count } do
      post sessions_passkey_path, params: { credential: assertion }, as: :json
    end
    assert_response :unprocessable_entity
  end

  private
    def random_challenge
      Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false)
    end

    def fake_credential(challenge)
      @client.create(challenge: challenge, rp_id: "www.example.com", user_verified: true)
    end
end
