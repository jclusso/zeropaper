require "test_helper"

# Outbound authorizes a chat when it is built and again right before each
# request. These tests make a document private in between, so they pass
# only because of the second check.
class Document::RequestReauthorizationTest < ActiveSupport::TestCase
  RESPONSES = "https://api.openai.com/v1/responses".freeze

  setup { configure_openai }

  test "a document made private after its chat was authorized is never sent" do
    document = ingest(BILL_TEXT, filename: "bill.txt")
    stub_request(:post, RESPONSES).to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })
    settings = Setting.instance
    chat = settings.provider_for(:extraction).chat(model: settings.model_for(:extraction))
    # Outbound has authorized the document by the time it asks the provider
    # for a chat; the document goes private right then.
    AIProvider.any_instance.stubs(:chat).with { Document.where(id: document.id).update_all(private: true, private_reason: "Marked private"); true }.returns(chat)

    document.process!

    assert_not_requested :post, RESPONSES
    assert_no_external_requests
    document.reload
    assert document.private?
    assert_nil document.ai_model
  end
end
