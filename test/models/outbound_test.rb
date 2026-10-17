require "test_helper"

class OutboundTest < ActiveSupport::TestCase
  RESPONSES = "https://api.openai.com/v1/responses".freeze
  MISTRAL_OCR = "https://api.mistral.ai/v1/ocr".freeze

  setup { configure_openai }

  test "refuses private documents" do
    document = ingest("secret", filename: "secret.txt", private: true)

    error = assert_raises(Outbound::PrivateDocumentError) { Outbound.for(document) }
    assert_match document.id.to_s, error.message
  end

  test "refuses a batch with any private document in it" do
    shareable = ingest("public", filename: "public.txt")
    secret = ingest("secret", filename: "secret.txt", private: true)

    assert_raises(Outbound::PrivateDocumentError) { Outbound.for([ shareable, secret ]) }
  end

  test "allows shareable documents and requests without documents" do
    shareable = ingest("public", filename: "public.txt")

    assert_equal [ shareable ], Outbound.for(shareable).documents
    assert_empty Outbound.without_documents.documents
  end

  test "release! returns shareable documents and refuses private ones" do
    shareable = ingest("public", filename: "public.txt")
    secret = ingest("secret", filename: "secret.txt", private: true)

    assert_equal [ shareable ], Outbound.release!([ shareable ])
    assert_raises(Outbound::PrivateDocumentError) { Outbound.release!([ secret ]) }
  end

  test "a missing document raises instead of being dropped" do
    shareable = ingest("public", filename: "public.txt")

    assert_raises(ArgumentError) { Outbound.for(nil) }
    assert_raises(ArgumentError) { Outbound.for(shareable, nil) }
    assert_raises(ArgumentError) { Outbound.for }
    assert_raises(ArgumentError) { Outbound.release!([ shareable, nil ]) }
  end

  test "privacy is read from the database, not from a stale object" do
    stale = ingest("public", filename: "public.txt")
    Document.where(id: stale.id).update_all(private: true)

    refute stale.private?
    assert_raises(Outbound::PrivateDocumentError) { Outbound.for(stale) }
    assert_raises(Outbound::PrivateDocumentError) { Outbound.release!([ stale ]) }
  end

  test "unsaved and deleted documents are refused" do
    deleted = ingest("public", filename: "public.txt")
    Document.where(id: deleted.id).delete_all

    assert_raises(Outbound::PrivateDocumentError) { Outbound.for(Document.new) }
    assert_raises(Outbound::PrivateDocumentError) { Outbound.for(deleted) }
  end

  test "a chat checks privacy again before each request, retries included" do
    document = ingest("public", filename: "public.txt")
    stub_request(:post, RESPONSES).to_return do
      Document.where(id: document.id).update_all(private: true)
      overloaded
    end

    assert_raises(Outbound::PrivateDocumentError) { Outbound.for(document).chat(:extraction).ask("Summarize it") }
    assert_requested :post, RESPONSES, times: 1
  end

  test "a chat retries as usual while its documents stay shareable" do
    document = ingest("public", filename: "public.txt")
    stub_request(:post, RESPONSES).to_return(overloaded, { status: 200, body: response_body("Done."), headers: { "Content-Type" => "application/json" } })

    response = Outbound.for(document).chat(:extraction).ask("Summarize it")

    assert_equal "Done.", response.content
    assert_requested :post, RESPONSES, times: 2
  end

  test "requests time out after two minutes unless given longer" do
    document = ingest("public", filename: "public.txt")

    assert_equal 120, Outbound.for(document).chat(:extraction).provider.connection.config.request_timeout
    assert_equal 600, Outbound.for(document).chat(:vision, timeout: 10.minutes).provider.connection.config.request_timeout
  end

  test "a timed out request is retried and the retry is logged" do
    document = ingest("public", filename: "public.txt")
    stub_request(:post, RESPONSES).to_timeout.then.to_return(status: 200, body: response_body("Done."), headers: { "Content-Type" => "application/json" })
    logged = StringIO.new
    Rails.stubs(:logger).returns(ActiveSupport::Logger.new(logged))

    response = Outbound.for(document).chat(:extraction).ask("Summarize it")

    assert_equal "Done.", response.content
    assert_requested :post, RESPONSES, times: 2
    assert_match(/\[outbound\] extraction request retried \(attempt 2\) after the last one ran \d+\.\ds/, logged.string)
  end

  test "the next turn of a chat is not logged as a retry" do
    document = ingest("public", filename: "public.txt")
    stub_request(:post, RESPONSES).to_return(status: 200, body: response_body("Done."), headers: { "Content-Type" => "application/json" })
    logged = StringIO.new
    Rails.stubs(:logger).returns(ActiveSupport::Logger.new(logged))

    chat = Outbound.for(document).chat(:extraction)
    chat.ask("Summarize it")
    chat.ask("Shorter")

    assert_requested :post, RESPONSES, times: 2
    refute_match "retried", logged.string
  end

  test "a chat checks documents released after it was built" do
    document = ingest("public", filename: "public.txt")
    outbound = Outbound.without_documents
    chat = outbound.chat(:research)
    outbound.release!([ document ])
    Document.where(id: document.id).update_all(private: true)

    assert_raises(Outbound::PrivateDocumentError) { chat.ask("What is in it?") }
    assert_not_requested :post, RESPONSES
  end

  test "OCR checks privacy again when it is called" do
    document = ingest("public", filename: "public.txt")
    outbound = Outbound.for(document)
    Document.where(id: document.id).update_all(private: true)
    AIProvider.any_instance.expects(:ocr).never

    assert_raises(Outbound::PrivateDocumentError) { outbound.ocr(fixture_file(".keep").to_s) }
    assert_no_external_requests
  end

  test "an OCR request checks privacy again before each retry" do
    use_mistral_ocr
    document = ingest("public", filename: "public.txt")
    stub_request(:post, MISTRAL_OCR).to_return do
      Document.where(id: document.id).update_all(private: true)
      overloaded
    end

    assert_raises(Outbound::PrivateDocumentError) { Outbound.for(document).ocr(fixture_file("../files/.keep").to_s) }
    assert_requested :post, MISTRAL_OCR, times: 1
  end

  test "an OCR request retries as usual while its document stays shareable" do
    use_mistral_ocr
    document = ingest("public", filename: "public.txt")
    page = { pages: [ { index: 0, markdown: "Scanned text" } ], model: "mistral-ocr-latest", usage_info: { pages_processed: 1 } }
    stub_request(:post, MISTRAL_OCR).to_return(overloaded, { status: 200, body: page.to_json, headers: { "Content-Type" => "application/json" } })

    result = Outbound.for(document).ocr(fixture_file("../files/.keep").to_s)

    assert_equal "Scanned text", result.markdown
    assert_requested :post, MISTRAL_OCR, times: 2
  end

  test "OCR is refused when its requests cannot be checked" do
    use_mistral_ocr
    document = ingest("public", filename: "public.txt")
    AIProvider.any_instance.stubs(:ocr).yields(stub(connection: Object.new))

    assert_raises(Outbound::Error) { Outbound.for(document).ocr(fixture_file("../files/.keep").to_s) }
    assert_no_external_requests
  end

  test "building a chat needs the task assigned" do
    Setting.instance.update!(ai_enabled: false)

    error = assert_raises(Outbound::NotConfiguredError) { Outbound.without_documents.chat(:research) }
    assert_match "“Research” under AI tasks", error.message
  end

  private
    def use_mistral_ocr
      mistral = AIProvider.create!(kind: "mistral", api_key: TestKeys::MISTRAL)
      Setting.instance.update!(vision_provider: mistral, vision_model: "mistral-ocr-latest")
    end

    def overloaded
      { status: 503, body: { error: { message: "Overloaded", type: "server_error" } }.to_json, headers: { "Content-Type" => "application/json" } }
    end

    def response_body(text)
      {
        id: "resp_1", object: "response", status: "completed", model: "gpt-5.6-luna",
        output: [ { type: "message", id: "msg_1", status: "completed", role: "assistant", content: [ { type: "output_text", text: text, annotations: [] } ] } ],
        usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 }
      }.to_json
    end
end

# Jobs run with the query cache on. Privacy changed by another process, on
# its own connection, must still stop the next request.
class OutboundQueryCacheTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "authorization reads privacy past the query cache" do
    document = document_with_text("public")
    outbound = Outbound.for(document)

    ActiveRecord::Base.cache do
      outbound.authorize!
      Thread.new { Document.where(id: document.id).update_all(private: true) }.join

      assert_raises(Outbound::PrivateDocumentError) { outbound.authorize! }
    end
  ensure
    Document.where(id: document.id).delete_all if document
  end
end
