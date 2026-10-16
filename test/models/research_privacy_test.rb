require "test_helper"

# Research runs with a stubbed provider that streams Chat Completions, so the
# test can read every request body the model would have received.
class ResearchPrivacyTest < ActiveSupport::TestCase
  COMPLETIONS = %r{\Ahttp://ollama\.test:11434/v1/chat/completions}

  setup do
    ollama = AIProvider.create!(kind: "ollama", base_url: "http://ollama.test:11434/v1")
    Setting.instance.update!(ai_enabled: true, research_provider: ollama, research_model: "llama3.1")

    @water = document_with_text("Harbor Water account 77-31. Amount due $41.20.", title: "Harbor water bill")
    @clinic = document_with_text("Lakeside Clinic visit. Referral for cardiology.", title: "Lakeside referral")
    [ @water, @clinic ].each(&:index!)
    @conversation = users(:one).conversations.create!(title: "Bills")
    @bodies = []
  end

  test "turns that used a document that is private now are left out of the next request" do
    @conversation.messages.create!(role: "user", content: "What did the clinic say?")
    @conversation.messages.create!(role: "assistant", status: "complete", content: "The clinic referred you to cardiology [##{@clinic.id}].",
      cited_document_ids: [ @clinic.id ], used_document_ids: [ @clinic.id ])
    @conversation.messages.create!(role: "user", content: "Anything else?")
    @conversation.messages.create!(role: "assistant", status: "complete", content: "Nothing else came up.")
    @clinic.update!(private: true)

    answer = ask("How much is the water bill?",
      tool_call("research--search_documents", query: "water bill"),
      text("The water bill is $41.20 [##{@water.id}]."))

    assert_equal "complete", answer.status, answer.content
    assert_equal 2, @bodies.size
    assert_includes @bodies.first, "Anything else?"
    @bodies.each do |body|
      refute_includes body, "Lakeside"
      refute_includes body, "cardiology"
      refute_includes body, "What did the clinic say?"
      refute_match(/"id"\s*:\s*#{@clinic.id}\b/, body)
    end
    assert_includes @bodies.last, "Harbor water bill"
    assert_equal [ @water.id ], answer.used_document_ids

    visible = @conversation.messages.where(role: "assistant", status: "complete").first
    assert_match "cardiology", visible.content, "the earlier answer stays visible"
  end

  test "a document made private during the run stops the next request" do
    second_response = lambda do |_request|
      Document.where(id: @water.id).update_all(private: true)
      sse(tool_call("research--read_document", id: @water.id))
    end

    answer = ask("How much is the water bill?",
      tool_call("research--search_documents", query: "water bill"),
      second_response,
      text("Done."))

    assert_equal "failed", answer.status
    assert_match "Private documents never leave this machine", answer.content
    assert_equal 2, @bodies.size, "no request after the document went private"
  end

  test "every document a tool returned is recorded, cited or not" do
    answer = ask("Any bills?",
      tool_call("research--search_documents", query: "bill"),
      text("There is a water bill."))

    assert_equal "complete", answer.status, answer.content
    assert_empty answer.cited_document_ids
    assert_includes answer.used_document_ids, @water.id
  end

  private
    def ask(question, *responses)
      @conversation.messages.create!(role: "user", content: question)
      message = @conversation.messages.create!(role: "assistant", status: "streaming")
      queue = responses.dup
      stub_request(:post, COMPLETIONS).to_return do |request|
        @bodies << request.body
        response = queue.shift
        response.respond_to?(:call) ? response.call(request) : sse(response)
      end

      Research.new(message).run
      message.reload
    end

    def tool_call(name, **arguments)
      { choices: [ { index: 0, delta: { role: "assistant", tool_calls: [ { index: 0, id: "call_#{SecureRandom.hex(4)}", type: "function",
        function: { name: name, arguments: arguments.to_json } } ] }, finish_reason: "tool_calls" } ] }
    end

    def text(content)
      { choices: [ { index: 0, delta: { role: "assistant", content: content }, finish_reason: "stop" } ] }
    end

    def sse(chunk)
      { status: 200, headers: { "Content-Type" => "text/event-stream" }, body: "data: #{chunk.to_json}\n\ndata: [DONE]\n\n" }
    end
end
