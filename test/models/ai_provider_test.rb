require "test_helper"

class AIProviderTest < ActiveSupport::TestCase
  test "hosted providers need a key and local ones need an address" do
    openai = AIProvider.new(kind: "openai")
    refute openai.valid?
    assert_includes openai.errors[:api_key], "is required for this provider"
    assert_includes openai.errors.full_messages, "API key is required for this provider"

    ollama = AIProvider.new(kind: "ollama")
    refute ollama.valid?
    assert_includes ollama.errors[:base_url], "is required for this provider"

    ollama.base_url = "localhost:11434"
    refute ollama.valid?
    assert_includes ollama.errors[:base_url], "must start with http:// or https://"

    ollama.base_url = "http://ollama:11434/"
    assert ollama.valid?
    assert_equal "http://ollama:11434", ollama.base_url
    assert_equal "Ollama", ollama.name
  end

  test "hosted providers list models from RubyLLM's registry, vision only when they read images" do
    anthropic = AIProvider.new(kind: "anthropic", api_key: TestKeys::ANTHROPIC)

    assert_includes anthropic.model_options(:extraction), "claude-haiku-4-5"
    assert anthropic.model_options(:vision).any?
    assert_equal "claude-haiku-4-5", anthropic.default_model(:extraction)
  end

  test "local servers are asked for their models" do
    ollama = AIProvider.create!(kind: "ollama", base_url: "http://ollama.test:11434")

    VCR.use_cassette("ai_providers/verify") do
      assert_equal [ "llama3.2-vision:11b", "qwen3:8b" ], ollama.model_options(:extraction)
    end
  end

  test "verify reports whether the key works" do
    VCR.use_cassette("ai_providers/verify") do
      assert AIProvider.new(kind: "openai", api_key: TestKeys::OPENAI).verify.ok?

      check = AIProvider.new(kind: "mistral", api_key: TestKeys::MISTRAL).verify
      refute check.ok?
      assert_equal "Mistral rejected the API key.", check.message
    end
  end

  test "an unreachable server is reported, not raised" do
    check = AIProvider.new(kind: "ollama", base_url: "http://ollama.invalid:11434").verify

    refute check.ok?
    assert_match "Could not reach Ollama", check.message
  end

  test "document details can come from Anthropic" do
    anthropic = AIProvider.create!(kind: "anthropic", api_key: TestKeys::ANTHROPIC)
    Setting.instance.update!(ai_enabled: true, extraction_provider: anthropic, extraction_model: "claude-haiku-4-5")
    document = ingest(BILL_TEXT, filename: "bill.txt")

    VCR.use_cassette("metadata/anthropic_electricity_bill") { process(document) }

    assert_equal "Acme Power Statement", document.title
    assert_equal correspondents(:acme_power), document.correspondent
    assert_equal "ai", document.metadata_source
    assert_equal "claude-haiku-4-5-20251001", document.ai_model
    assert_requested :post, "https://api.anthropic.com/v1/messages", headers: { "X-Api-Key" => TestKeys::ANTHROPIC }
    assert_not_requested :any, %r{api\.openai\.com}
  end

  test "each task uses its own provider" do
    openai = configure_openai
    anthropic = AIProvider.create!(kind: "anthropic", api_key: TestKeys::ANTHROPIC)
    Setting.instance.update!(research_provider: anthropic, research_model: "claude-sonnet-4-5")

    assert_equal openai, Setting.instance.provider_for(:extraction)
    assert_equal anthropic, Setting.instance.provider_for(:research)
    assert_equal "Anthropic · claude-sonnet-4-5", Outbound.model_label(:research)
  end

  test "removing a provider unassigns its tasks" do
    openai = configure_openai
    openai.destroy

    assert_nil Setting.instance.reload.extraction_provider
    refute Setting.instance.ai_configured?
  end

  test "scans are read by the vision model when AI is on, otherwise locally" do
    settings = Setting.instance
    document = Document.new(private: false)
    assert_equal "Tesseract (local)", settings.active_ocr_label
    refute settings.ai_reads_scans_for?(document)

    configure_openai
    settings.reload
    assert settings.ai_reads_scans_for?(document)
    refute settings.ai_reads_scans_for?(Document.new(private: true))
    assert_equal "OpenAI · gpt-5.6-luna", settings.active_ocr_label

    settings.update!(ai_enabled: false)
    refute settings.ai_reads_scans_for?(document)
  end

  test "Mistral's OCR models are offered for the vision task and read through the OCR API" do
    mistral = AIProvider.new(kind: "mistral", api_key: TestKeys::MISTRAL)

    assert_includes mistral.model_options(:vision), "mistral-ocr-latest"
    assert_equal "mistral-ocr-latest", mistral.default_model(:vision)
    assert mistral.ocr_model?("mistral-ocr-latest")
    refute mistral.ocr_model?("mistral-medium-latest")
  end
end
