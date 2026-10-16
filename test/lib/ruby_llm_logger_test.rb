require "test_helper"

class RubyLLMLoggerTest < ActiveSupport::TestCase
  setup do
    @logged = StringIO.new
    @rails_logger = ActiveSupport::Logger.new(@logged, level: :debug)
  end

  test "stays at info even when asked for debug" do
    logger = RubyLLMLogger.new(@rails_logger)
    logger.level = :debug

    refute logger.debug?
    logger.debug("request body: Biopsy results")
    logger.info("POST https://api.openai.com/v1/chat/completions")

    refute_match "Biopsy", @logged.string
    assert_match "POST https://api.openai.com", @logged.string
  end

  test "a request does not log its body when the Rails log is at debug" do
    stub_request(:post, %r{\Ahttps://api.openai.com/}).to_return(status: 400, body: "{}")
    Rails.stubs(:logger).returns(@rails_logger)
    load Rails.root.join("config/initializers/ruby_llm.rb")
    RubyLLM.instance_variable_set(:@logger, nil)

    assert_raises(RubyLLM::Error) do
      RubyLLM.context { |config| config.openai_api_key = "test" }
        .chat(model: "gpt-4.1-mini", provider: :openai, assume_model_exists: true)
        .ask("Biopsy results for Jane")
    end

    refute_match "Biopsy", @logged.string
    refute RubyLLM.logger.debug?
  ensure
    Rails.unstub(:logger)
    load Rails.root.join("config/initializers/ruby_llm.rb")
    RubyLLM.instance_variable_set(:@logger, nil)
  end
end
