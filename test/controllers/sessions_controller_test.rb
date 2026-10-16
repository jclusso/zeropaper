require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  include CableDisconnects

  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "the session cookie is secure over HTTPS" do
    https!
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_match(/session_id=[^;]+;.*secure/i, Array(response.headers["Set-Cookie"]).join("\n"))
  end

  test "the session cookie is not marked secure over plain HTTP on a LAN install" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    cookie = Array(response.headers["Set-Cookie"]).join("\n")
    assert_match "session_id=", cookie
    assert_no_match(/secure/i, cookie)
  end

  test "an idle session is signed out and destroyed" do
    sign_in_as(@user)
    session = Current.session

    travel Session::IDLE_TIMEOUT + 1.day do
      get documents_path

      assert_redirected_to new_session_path
      refute Session.exists?(session.id)
    end
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(User.take)
    session = Current.session

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
    assert_equal 1, cable_disconnects(session)
  end
end
