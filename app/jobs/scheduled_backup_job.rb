class ScheduledBackupJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "backup", duration: 6.hours

  def perform
    Backup.run_scheduled
  end
end
