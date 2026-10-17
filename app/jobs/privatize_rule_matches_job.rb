class PrivatizeRuleMatchesJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(rule)
    rule.privatize_existing!
  end
end
