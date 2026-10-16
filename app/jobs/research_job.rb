class ResearchJob < ApplicationJob
  queue_as :research

  discard_on ActiveJob::DeserializationError

  def perform(message)
    Research.new(message).run
  end
end
