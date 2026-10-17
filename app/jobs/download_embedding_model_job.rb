class DownloadEmbeddingModelJob < ApplicationJob
  queue_as :default
  # Every document that reaches indexing before the model is ready asks for
  # it, so one download runs and the rest are dropped. The lock outlasts a
  # slow download, so a second one never starts alongside it.
  limits_concurrency to: 1, key: "embedding-model", on_conflict: :discard, duration: 1.hour

  # Documents processed while the model was missing are indexed now.
  def perform
    Embedder.download unless Embedder.downloaded?
    Document.index_waiting_later
  rescue StandardError => error
    Rails.logger.warn("[embedder] model download failed, will retry when a document needs it: #{error.message}")
  end
end
