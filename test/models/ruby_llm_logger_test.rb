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

  test "is RubyLLM's logger" do
    assert_kind_of RubyLLMLogger, RubyLLM.config.logger
    assert_kind_of RubyLLMLogger, RubyLLM.logger
  end

  test "a request does not log its body when the Rails log is at debug" do
    stub_request(:post, %r{\Ahttps://api.openai.com/}).to_return(status: 400, body: "{}")
    RubyLLM.stubs(:logger).returns(RubyLLMLogger.new(@rails_logger))

    assert_raises(RubyLLM::Error) do
      RubyLLM.context { |config| config.openai_api_key = "test" }
        .chat(model: "gpt-4.1-mini", provider: :openai, assume_model_exists: true)
        .ask("Biopsy results for Jane")
    end

    refute_match "Biopsy", @logged.string
  end
end
