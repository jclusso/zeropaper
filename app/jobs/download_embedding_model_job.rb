class DownloadEmbeddingModelJob < ApplicationJob
  queue_as :default

  def perform
    Embedder.download unless Embedder.downloaded?
  rescue StandardError => error
    Rails.logger.warn("[embedder] model download failed, will retry on first use: #{error.message}")
  end
end
