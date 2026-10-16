require "test_helper"

class OutboundTest < ActiveSupport::TestCase
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

  test "building a chat needs the task assigned" do
    Setting.instance.update!(ai_enabled: false)

    error = assert_raises(Outbound::NotConfiguredError) { Outbound.without_documents.chat(:research) }
    assert_match "“Research” under AI tasks", error.message
  end
end
