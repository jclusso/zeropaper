# Counts the disconnect messages Action Cable sent to a session's open
# connections, which are identified by user and session.
module CableDisconnects
  extend ActiveSupport::Concern

  included do
    include ActionCable::TestHelper
  end

  private
    def cable_disconnects(session)
      channel = "action_cable/#{[ session.user, session ].map(&:to_gid_param).sort.join(":")}"
      broadcasts(channel).count { |message| JSON.parse(message)["type"] == "disconnect" }
    end
end
