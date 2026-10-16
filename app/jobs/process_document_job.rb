class ProcessDocumentJob < ApplicationJob
  queue_as :processing
  # One run per document at a time. The lock outlasts the longest run (OCR
  # alone may take 30 minutes), so a second run never overlaps the first.
  limits_concurrency to: 1, key: ->(document, **) { document }, duration: 1.hour

  discard_on ActiveJob::DeserializationError

  def perform(document, extract_metadata: true)
    document.process!(extract_metadata: extract_metadata)
  end
end
