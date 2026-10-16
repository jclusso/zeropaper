class BackupJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "backup", duration: 6.hours

  def perform(backup)
    backup.process!
  end
end
