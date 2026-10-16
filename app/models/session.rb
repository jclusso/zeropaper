# A signed-in browser. Sessions end after IDLE_TIMEOUT without a request, so
# a forgotten or stolen cookie stops working on its own.
class Session < ApplicationRecord
  IDLE_TIMEOUT = 30.days
  # Activity is recorded at most this often, not on every request.
  ACTIVITY_INTERVAL = 1.hour

  belongs_to :user

  before_create -> { self.last_active_at ||= Time.current }

  # The session for a cookie's id, or nil. An idle one is destroyed instead.
  def self.resume(id)
    session = find_by(id: id) or return
    if session.expired?
      session.destroy
      nil
    else
      session.tap(&:record_activity)
    end
  end

  def expired?
    (last_active_at || updated_at) < IDLE_TIMEOUT.ago
  end

  def record_activity
    update_column(:last_active_at, Time.current) if last_active_at.nil? || last_active_at < ACTIVITY_INTERVAL.ago
  end
end
