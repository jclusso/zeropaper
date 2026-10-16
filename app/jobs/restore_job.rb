class RestoreJob < ApplicationJob
  queue_as :default

  def perform(restore)
    restore.process!
  end
end
