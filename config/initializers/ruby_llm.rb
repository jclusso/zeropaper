# Provider keys live in the database (AIProvider) and are applied per call
# through RubyLLM.context in Outbound, so nothing global is configured here
# beyond the logger, which keeps request bodies out of the log.
Rails.application.config.to_prepare do
  RubyLLM.configure { |config| config.logger = RubyLLMLogger.new(Rails.logger) }
end
