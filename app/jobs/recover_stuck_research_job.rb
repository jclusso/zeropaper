class RecoverStuckResearchJob < ApplicationJob
  queue_as :default

  def perform
    Message.recover_stuck
  end
end
