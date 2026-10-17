require "test_helper"

class SessionTest < ActiveSupport::TestCase
  include CableDisconnects

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
    assert_equal 1, cable_disconnects(@session)
  end

  test "ending a session closes its open connections and no others" do
    other = users(:one).sessions.create!

    @session.destroy

    assert_equal 1, cable_disconnects(@session)
    assert_equal 0, cable_disconnects(other)
  end

  test "idle sessions are ended even if nobody comes back to them" do
    active = users(:two).sessions.create!

    travel Session::IDLE_TIMEOUT + 1.minute do
      active.update_column(:last_active_at, Time.current)
      ExpireSessionsJob.perform_now
    end

    refute Session.exists?(@session.id)
    assert Session.exists?(active.id)
    assert_equal 1, cable_disconnects(@session)
    assert_equal 0, cable_disconnects(active)
  end

  test "deleting a user closes their sessions' connections" do
    user = User.create!(name: "Temp", email_address: "temp@example.com", password: "password")
    session = user.sessions.create!

    User.find(user.id).destroy

    assert_equal 1, cable_disconnects(session)
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
