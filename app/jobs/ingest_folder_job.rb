class IngestFolderJob < ApplicationJob
  queue_as :ingest
  limits_concurrency to: 1, key: "ingest_folder"

  def perform
    Ingest::Folder.new.scan if Setting.instance.ingest_enabled?
  end
end
