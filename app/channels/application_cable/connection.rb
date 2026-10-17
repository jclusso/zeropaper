module ApplicationCable
  # Identified by session as well as user, so ending a session (Session
  # disconnects on destroy) closes the sockets it opened and no others.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_session

    def connect
      set_current_session || reject_unauthorized_connection
    end

    private
      # Session.resume refuses, and destroys, a session that has gone idle.
      def set_current_session
        if session = Session.resume(cookies.signed[:session_id])
          self.current_session = session
          self.current_user = session.user
        end
      end
  end
end
