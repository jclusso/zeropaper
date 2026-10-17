# A signed-in browser. Sessions end after IDLE_TIMEOUT without a request, so
# a forgotten or stolen cookie stops working on its own. Ending one, however
# it happens, also closes its open Action Cable connections, so live updates
# stop with it.
class Session < ApplicationRecord
  IDLE_TIMEOUT = 30.days
  # Activity is recorded at most this often, not on every request.
  ACTIVITY_INTERVAL = 1.hour

  belongs_to :user

  before_create -> { self.last_active_at ||= Time.current }
  after_destroy_commit :disconnect_cable

  scope :idle, -> { where("COALESCE(last_active_at, updated_at) < ?", IDLE_TIMEOUT.ago) }

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

  # Ends idle sessions nobody has come back to, which would otherwise only
  # end on their next request.
  def self.expire_idle
    idle.find_each(&:destroy)
  end

  def expired?
    (last_active_at || updated_at) < IDLE_TIMEOUT.ago
  end

  def record_activity
    update_column(:last_active_at, Time.current) if last_active_at.nil? || last_active_at < ACTIVITY_INTERVAL.ago
  end

  private
    def disconnect_cable
      ActionCable.server.remote_connections.where(current_user: user, current_session: self).disconnect
    end
end
