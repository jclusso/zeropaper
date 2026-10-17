require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  setup { @session = users(:one).sessions.create! }

  test "connects with a signed-in session, identified by user and session" do
    cookies.signed[:session_id] = @session.id

    connect

    assert_equal users(:one), connection.current_user
    assert_equal @session, connection.current_session
  end

  test "refuses a connection without a session" do
    assert_reject_connection { connect }
  end

  test "refuses an idle session and ends it" do
    cookies.signed[:session_id] = @session.id

    travel Session::IDLE_TIMEOUT + 1.minute do
      assert_reject_connection { connect }
    end
    refute Session.exists?(@session.id)
  end

  test "refuses a session that has been signed out" do
    cookies.signed[:session_id] = @session.id
    @session.destroy

    assert_reject_connection { connect }
  end
end
