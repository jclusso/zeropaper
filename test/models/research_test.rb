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

  test "after 20 tool calls the model must answer with what it has and the answer says so" do
    chat = scripted_chat(calls_per_turn: 3)

    @research.run

    @message.reload
    assert_equal "complete", @message.status
    assert_equal Research::MAX_TOOL_CALLS, chat.executed.size, "no tool ran past the limit"
    assert_equal 21, chat.called.size, "the call after the limit in the same turn was refused"
    assert_match "Acme Power counted.", @message.content
    assert_match "Research stopped after 20 lookups", @message.content
    assert_equal :none, chat.tool_options[:choice]
  end

  test "an answer within the limit has no note" do
    scripted_chat(calls_per_turn: 1, answer_after: 2)

    @research.run

    assert_equal "Acme Power counted.", @message.reload.content
  end

  test "a model that ignores the limit is stopped" do
    chat = scripted_chat(calls_per_turn: 5, obey_limit: false)

    @research.run

    assert_equal "failed", @message.reload.status
    assert_match "kept looking things up", @message.content
    assert_equal Research::MAX_TOOL_CALLS, chat.executed.size
  end

  test "without an AI key the answer fails with an explanation and nothing is sent" do
    Setting.instance.update!(ai_enabled: false)

    @research.run

    assert_equal "failed", @message.reload.status
    assert_match "Choose a provider and model", @message.content
    assert_no_external_requests
  end

  test "a failure is logged by class and message id, never by its message" do
    Outbound.any_instance.stubs(:chat).raises(RuntimeError, "provider said: Biopsy results for Jane")
    logged = StringIO.new
    Rails.stubs(:logger).returns(ActiveSupport::Logger.new(logged))

    @research.run

    assert_equal "failed", @message.reload.status
    assert_match "[research] message #{@message.id}: RuntimeError", logged.string
    refute_match "Biopsy", logged.string
  end

  # A model that asks for count_documents +calls_per_turn+ times a turn, and
  # answers after +answer_after+ turns or once tools are switched off. Tools,
  # callbacks and the loop are RubyLLM's own; only the provider is scripted.
  module ScriptedModel
    attr_accessor :calls_per_turn, :answer_after, :obey_limit
    attr_reader :called, :executed

    def generate(&)
      @turns = @turns.to_i + 1
      if (obey_limit && tool_options[:choice] == :none) || (answer_after && @turns > answer_after)
        return add_message(role: :assistant, content: "Acme Power counted.")
      end

      tool_name = tools.keys.find { |name| name.to_s.include?("count_documents") }.to_s
      calls = Array.new(calls_per_turn) do |index|
        id = "call_#{@turns}_#{index}"
        [ id, RubyLLM::ToolCall.new(id: id, name: tool_name, arguments: { "group_by" => "correspondent" }) ]
      end.to_h
      add_message(role: :assistant, content: "", tool_calls: calls)
    end
  end

  private
    def scripted_chat(calls_per_turn:, answer_after: nil, obey_limit: true)
      openai = configure_openai
      chat = openai.chat(model: "gpt-5.6").extend(ScriptedModel)
      chat.calls_per_turn = calls_per_turn
      chat.answer_after = answer_after
      chat.obey_limit = obey_limit
      chat.instance_variable_set(:@called, [])
      chat.instance_variable_set(:@executed, [])
      chat.before_tool_call { |tool_call| chat.called << tool_call.id }
      Research::CountDocuments.any_instance.stubs(:execute).with { |**| chat.executed << true }.returns({ counts: { "Acme Power" => 1 } })
      AIProvider.any_instance.stubs(:chat).returns(chat)
      chat
    end
end
