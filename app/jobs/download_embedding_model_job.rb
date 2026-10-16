class DownloadEmbeddingModelJob < ApplicationJob
  queue_as :default
  # Every document that reaches indexing before the model is ready asks for
  # it, so one download runs and the rest are dropped.
  limits_concurrency to: 1, key: "embedding-model", on_conflict: :discard

  def perform
    Embedder.download unless Embedder.downloaded?
  rescue StandardError => error
    Rails.logger.warn("[embedder] model download failed, will retry when a document needs it: #{error.message}")
  end
end
