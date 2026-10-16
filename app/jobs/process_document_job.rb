class ProcessDocumentJob < ApplicationJob
  queue_as :processing
  limits_concurrency to: 1, key: ->(document, **) { document }

  discard_on ActiveJob::DeserializationError

  def perform(document, extract_metadata: true)
    document.process!(extract_metadata: extract_metadata)
  end
end
