require "test_helper"

class Metadata::AITest < ActiveSupport::TestCase
  setup { configure_openai }

  test "applies the details the model returns" do
    document = ingest(BILL_TEXT, filename: "bill.txt")

    VCR.use_cassette("metadata/openai_electricity_bill") { process(document) }

    assert_equal "Acme Power Electricity Bill", document.title
    assert_equal Date.new(2026, 3, 14), document.document_date
    assert_equal correspondents(:acme_power), document.correspondent
    assert_equal document_types(:invoice), document.document_type
    assert_equal %w[Electricity Utilities], document.tags.map(&:name).sort
    assert_match "Amount due $87.40", document.summary
    assert_equal "ai", document.metadata_source
    assert_equal "gpt-5.6-luna-2026-07-01", document.ai_model
    assert_in_delta 0.55, document.confidence
  end

  test "types and tags the AI invents start without auto-match, correspondents keep it" do
    configure_openai(ai_creates_types: true, ai_creates_tags: true)
    document = ingest(BILL_TEXT, filename: "bill.txt")

    VCR.use_cassette("metadata/openai_electricity_bill") { process(document) }

    invented = Tag.find_by!(name: "Electricity")
    refute invented.auto_match?, "a tag the AI made up does not match by name"
    assert Tag.find_or_create_named("Garden Supplies").auto_match?, "a tag you add yourself matches by name"
    assert Correspondent.find_or_create_named("New Utility Co").auto_match?
  end

  test "a correspondent the AI adds keeps auto-match and is remembered as new for this document" do
    correspondents(:acme_power).destroy
    document = ingest(BILL_TEXT, filename: "bill.txt")

    VCR.use_cassette("metadata/openai_electricity_bill") { process(document) }

    assert_equal "Acme Power", document.correspondent.name
    assert document.correspondent.auto_match?
    assert document.ai_created_correspondent?

    document.update!(correspondent: correspondents(:city_clinic))
    refute document.ai_created_correspondent?
  end

  test "an existing correspondent is not marked new" do
    document = ingest(BILL_TEXT, filename: "bill.txt")

    VCR.use_cassette("metadata/openai_electricity_bill") { process(document) }

    assert_equal correspondents(:acme_power), document.correspondent
    refute document.ai_created_correspondent?
  end

  test "the model is asked for a proper name, not a category" do
    description = Metadata::AI::SCHEMA.dig(:properties, :correspondent, :description)

    assert_match "proper name as printed on the document", description
    assert_match "never a category like 'Bank' or 'Insurance'", description
  end

  test "sends the text and the extraction model" do
    document = ingest(BILL_TEXT, filename: "bill.txt")

    VCR.use_cassette("metadata/openai_electricity_bill") { process(document) }

    assert_requested(:post, "https://api.openai.com/v1/responses", times: 1) do |request|
      body = JSON.parse(request.body)
      body["model"] == "gpt-5.6-luna" && body.to_json.include?("Account 55-0192") &&
        body.dig("text", "format", "type") == "json_schema"
    end
  end

  test "low confidence sends the document to the inbox" do
    document = ingest(BILL_TEXT, filename: "bill.txt")

    VCR.use_cassette("metadata/openai_electricity_bill") { process(document) }

    assert document.needs_review?
    assert_includes document.review_reasons, "low_confidence"
  end

  test "names only used by private documents are not offered to the model" do
    secret = Correspondent.create!(name: "Discreet Therapy Practice", auto_match: false)
    document_with_text("private notes", private: true, correspondent: secret)
    document = ingest(BILL_TEXT, filename: "bill.txt")

    VCR.use_cassette("metadata/openai_electricity_bill") { process(document) }

    assert_requested(:post, "https://api.openai.com/v1/responses") { |request| request.body.include?("Acme Power") }
    assert_not_requested(:post, "https://api.openai.com/v1/responses") { |request| request.body.include?("Discreet Therapy") }
  end

  test "documents whose titles are offered as examples are checked again before each attempt" do
    example = document_with_text("Harbor Water account 77-31", title: "Harbor Water Bill", metadata_source: "ai")
    document = ingest(BILL_TEXT, filename: "bill.txt")
    stub_request(:post, "https://api.openai.com/v1/responses").to_return do
      Document.where(id: example.id).update_all(private: true)
      { status: 503, body: { error: { message: "Overloaded", type: "server_error" } }.to_json, headers: { "Content-Type" => "application/json" } }
    end

    error = assert_raises(Outbound::PrivateDocumentError) { Metadata::AI.new(document).apply }

    assert_match example.id.to_s, error.message
    assert_requested(:post, "https://api.openai.com/v1/responses", times: 1) { |request| request.body.include?("Harbor Water Bill") }
  end

  test "an example title turning private files the document with local rules" do
    example = document_with_text("Harbor Water account 77-31", title: "Harbor Water Bill", metadata_source: "ai")
    document = ingest(BILL_TEXT, filename: "bill.txt")
    stub_request(:post, "https://api.openai.com/v1/responses").to_return do
      Document.where(id: example.id).update_all(private: true)
      { status: 503, body: { error: { message: "Overloaded", type: "server_error" } }.to_json, headers: { "Content-Type" => "application/json" } }
    end

    process(document)

    assert_equal "ready", document.status
    assert_equal "rules", document.metadata_source
    assert_includes document.review_reasons, "ai_failed"
    assert_equal correspondents(:acme_power), document.correspondent
    refute_match example.id.to_s, document.step_state("metadata")["detail"]
  end

  test "tags the AI invents are created in name order" do
    configure_openai(ai_creates_tags: true)
    document = ingest(BILL_TEXT, filename: "bill.txt")
    details = { title: "Bill", document_date: nil, correspondent: nil, document_type: nil, tags: %w[Zinc apple Mango], summary: "", confidence: 0.9 }
    stub_request(:post, "https://api.openai.com/v1/responses").to_return(status: 200, body: response_body(details.to_json), headers: { "Content-Type" => "application/json" })

    Metadata::AI.new(document).apply

    assert_equal %w[apple Mango Zinc], Tag.where(name: %w[Zinc apple Mango]).order(:id).pluck(:name)
  end

  test "manually edited details are kept" do
    document = ingest(BILL_TEXT, filename: "bill.txt")
    document.update!(title: "My power bill", metadata_source: "manual")

    VCR.use_cassette("metadata/openai_electricity_bill") { Metadata::AI.new(document).apply }

    assert_equal "My power bill", document.reload.title
    assert_equal "manual", document.metadata_source
    assert_equal correspondents(:acme_power), document.correspondent
  end

  test "falls back to local rules when the request fails" do
    stub_request(:post, "https://api.openai.com/v1/responses").to_return(status: 401, body: { error: { message: "bad key" } }.to_json)
    document = process(ingest(BILL_TEXT, filename: "bill.txt"))

    assert_equal "rules", document.metadata_source
    assert_includes document.review_reasons, "ai_failed"
    assert_equal correspondents(:acme_power), document.correspondent
  end

  private
    def response_body(text)
      {
        id: "resp_1", object: "response", status: "completed", model: "gpt-5.6-luna",
        output: [ { type: "message", id: "msg_1", status: "completed", role: "assistant", content: [ { type: "output_text", text: text, annotations: [] } ] } ],
        usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 }
      }.to_json
    end
end
