require "test_helper"

class ResearchTest < ActiveSupport::TestCase
  setup do
    @bill = document_with_text(BILL_TEXT, title: "Electricity statement", correspondent: correspondents(:acme_power))
    @private_bill = document_with_text("Electricity statement for the clinic apartment", title: "Clinic electricity", private: true,
      correspondent: correspondents(:acme_power))
    [ @bill, @private_bill ].each(&:index!)

    conversation = users(:one).conversations.create!(title: "Bills")
    conversation.messages.create!(role: "user", content: "How much was the electricity bill?")
    @message = conversation.messages.create!(role: "assistant", status: "streaming")
    @research = Research.new(@message)
  end

  test "search hands the model only shareable documents and remembers private matches" do
    result = Research::SearchDocuments.new(@research).execute(query: "electricity statement")
    ids = result[:results].map { |found| found[:id] }

    assert_includes ids, @bill.id
    assert_not_includes ids, @private_bill.id
    assert_includes @research.private_match_ids, @private_bill.id
    assert_includes @research.cited_ids, @bill.id
    refute(result.to_s.include?("clinic apartment"))
  end

  test "reading a private document is refused" do
    assert_equal({ error: "No document with id #{@private_bill.id} is available." }, Research::ReadDocument.new(@research).execute(id: @private_bill.id))
  end

  test "reading a document returns its pages" do
    result = Research::ReadDocument.new(@research).execute(id: @bill.id)

    assert_equal "Electricity statement", result[:title]
    assert_match "[page 1]", result[:text]
    assert_match "Amount due: $87.40", result[:text]
  end

  test "counts leave private documents out" do
    counts = Research::CountDocuments.new(@research).execute(group_by: "correspondent")[:counts]

    assert_equal({ "Acme Power" => 1 }, counts)
  end

  test "taxonomy lists only names with shareable documents" do
    Correspondent.create!(name: "Secret Surgeon").tap { |surgeon| @private_bill.update!(correspondent: surgeon) }

    names = Research::ListTaxonomy.new(@research).execute[:correspondents].keys
    assert_includes names, "Acme Power"
    assert_not_includes names, "Secret Surgeon"
  end

  test "steps name the document being read, never a private one" do
    shareable = RubyLLM::ToolCall.new(id: "call_1", name: "research--read_document", arguments: { "id" => @bill.id })
    secret = RubyLLM::ToolCall.new(id: "call_2", name: "research--read_document", arguments: { "id" => @private_bill.id })

    assert_equal "Reading “Electricity statement”", @research.send(:step_label, shareable)
    assert_equal "Reading document ##{@private_bill.id}", @research.send(:step_label, secret)
  end

  test "without an AI key the answer fails with an explanation and nothing is sent" do
    Setting.instance.update!(ai_enabled: false)

    @research.run

    assert_equal "failed", @message.reload.status
    assert_match "Choose a provider and model", @message.content
    assert_no_external_requests
  end
end
