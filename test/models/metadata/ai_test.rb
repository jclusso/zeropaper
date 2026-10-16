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
end
