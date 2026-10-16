require "test_helper"

class Documents::PrivaciesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "making a document not private asks first and names where it will be sent" do
    configure_openai
    document = ingest("Form 1040", filename: "notes.txt", private: true)

    get document_path(document)

    assert_select "form[action=?][data-turbo-confirm]", document_privacy_path(document) do |forms|
      assert_match "will be sent to the AI providers in Settings: OpenAI · gpt-5.6-luna and OpenAI · gpt-5.6", forms.sole["data-turbo-confirm"]
    end
  end

  test "making a document not private queues it for processing" do
    document = ingest("Form 1040", filename: "notes.txt", private: true)

    assert_enqueued_with(job: ProcessDocumentJob) { delete document_privacy_path(document) }

    assert_redirected_to document_path(document)
    refute document.reload.private?
  end

  test "making a document not private is refused while a filename rule applies" do
    Rule.create!(name: "Tax files", conditions: [ { field: "filename", operator: "any", value: "tax" } ], mark_private: true)
    document = ingest("Form 1040", filename: "2025 tax.txt")

    assert_no_enqueued_jobs(only: ProcessDocumentJob) { delete document_privacy_path(document) }

    assert_redirected_to document_path(document)
    assert_match "“Tax files” still marks this document private", flash[:alert]
    assert document.reload.private?
  end
end
