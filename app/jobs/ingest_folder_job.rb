class IngestFolderJob < ApplicationJob
  queue_as :ingest
  # Runs every second, so a scan of a slow share that overlaps the next run
  # drops that run instead of queueing behind it.
  limits_concurrency to: 1, key: "ingest_folder", on_conflict: :discard

  def perform
    Ingest::Folder.new.scan if Setting.instance.ingest_enabled?
  end
end
