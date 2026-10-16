# Rebuilds one document's indexes and nothing else. Shares the processing
# run's concurrency key, so it never overlaps a run on the same document.
class IndexDocumentJob < ApplicationJob
  queue_as :processing
  limits_concurrency to: 1, key: ->(document) { document }, group: "ProcessDocumentJob", duration: 1.hour

  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  # Declared last so it is checked first: a deleted document is not retried.
  discard_on ActiveJob::DeserializationError

  # A queued or running processing run indexes the document itself.
  def perform(document)
    document.index_now! unless document.processing?
  end
end
