class ExpireSessionsJob < ApplicationJob
  queue_as :default

  def perform
    Session.expire_idle
  end
end
