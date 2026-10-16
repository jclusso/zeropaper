require "test_helper"
require "webauthn/fake_client"

class PasskeysControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

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
        post passkeys_path, params: { credential: fake_credential(response.parsed_body["challenge"]), name: "MacBook" }, as: :json
      end
    end
    assert_equal({ "location" => profile_path }, response.parsed_body)
  end

  test "no email is sent when outgoing mail is not set up" do
    ApplicationMailer.stubs(:delivery_method).returns(:smtp)
    ApplicationMailer.stubs(:smtp_settings).returns(address: "localhost", port: 25)
    post passkeys_challenge_path, params: { current_password: "password" }, as: :json

    assert_difference -> { @user.passkeys.count } do
      assert_no_enqueued_emails do
        post passkeys_path, params: { credential: fake_credential(response.parsed_body["challenge"]), name: "MacBook" }, as: :json
      end
    end
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
