# Provider keys live in the database (AIProvider) and are applied per call
# through RubyLLM.context in Outbound, so nothing global is configured here.
RubyLLM.configure do |config|
  config.logger = Rails.logger
end
