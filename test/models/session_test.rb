require "test_helper"

class SessionTest < ActiveSupport::TestCase
  setup { @session = users(:one).sessions.create! }

  test "a new session starts active" do
    assert_in_delta Time.current, @session.last_active_at, 1.second
    refute @session.expired?
  end

  test "a session idle for 30 days is destroyed instead of resumed" do
    travel Session::IDLE_TIMEOUT + 1.minute do
      assert_nil Session.resume(@session.id)
    end

    refute Session.exists?(@session.id)
  end

  test "activity is recorded at most once an hour" do
    travel 30.minutes do
      Session.resume(@session.id)
      assert_in_delta 30.minutes.ago, @session.reload.last_active_at, 1.second
    end

    travel 2.hours do
      Session.resume(@session.id)
      assert_in_delta Time.current, @session.reload.last_active_at, 1.second
    end
  end

  test "recent activity keeps a session alive past 30 days from sign in" do
    travel 20.days do
      Session.resume(@session.id)
    end

    travel 40.days do
      assert_equal @session, Session.resume(@session.id)
    end
  end

  test "a session from before activity was tracked expires by its last update" do
    @session.update_columns(last_active_at: nil, updated_at: 31.days.ago)

    assert_nil Session.resume(@session.id)
  end
end
