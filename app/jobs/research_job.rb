class ResearchJob < ApplicationJob
  queue_as :research
  limits_concurrency to: 1, key: ->(message) { message }, duration: 30.minutes

  discard_on ActiveJob::DeserializationError

  def perform(message)
    message.research!
  end
end
