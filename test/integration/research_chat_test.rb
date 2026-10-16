require "test_helper"

class ResearchChatTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @conversation = users(:one).conversations.create!(title: "When was the car last inspected?")
  end

  test "a new research page offers example questions" do
    configure_openai

    get conversations_path

    assert_response :success
    assert_select "h1", text: "What do you want to know?"
    assert_select "button[data-action='chat#fill']", count: 3
    assert_select "textarea[name=question][data-chat-target=input]"
    assert_select "a", text: @conversation.title
  end

  test "without a research model the page says how to set it up" do
    get conversations_path

    assert_select "textarea[name=question]", count: 0
    assert_match "Research needs AI turned on", response.body
  end

  test "questions are bubbles and answers are prose with citations and sources" do
    cited = document_with_text("Inspection passed on May 2, 2026", title: "Vehicle inspection", document_date: Date.new(2026, 5, 2))
    secret = document_with_text("Private note", private: true)
    @conversation.messages.create!(role: "user", content: "When was the car\nlast inspected?")
    @conversation.messages.create!(role: "assistant", status: "complete",
      content: "## Answer\n\nThe car passed inspection on **May 2, 2026** [##{cited.id}].\n\n- Odometer: 34,906",
      steps: [ { "label" => "Searching for “car inspection”" }, { "label" => "Reading document ##{cited.id}" } ],
      cited_document_ids: [ cited.id ], private_match_ids: [ secret.id ])

    get conversation_path(@conversation)

    assert_response :success
    assert_select "h1.truncate", text: @conversation.title
    assert_select "div.justify-end div.whitespace-pre-wrap", text: /When was the car\s+last inspected\?/
    assert_includes response.body, "When was the car\nlast inspected?"
    assert_select "article[data-message-status=complete]" do
      assert_select "summary", text: /Researched · 2 steps/
      assert_select "ol li", text: "Reading “Vehicle inspection”"
      assert_select ".prose-answer h2", text: "Answer"
      assert_select ".prose-answer strong", text: "May 2, 2026"
      assert_select ".prose-answer li", text: "Odometer: 34,906"
      assert_select ".prose-answer a.citation[href=?]", document_path(cited), text: "Vehicle inspection"
      assert_select "p", text: "Sources"
      assert_select "a.flex[href=?]", document_path(cited), text: /Vehicle inspection.*May 2, 2026/m
      assert_select "p", text: /1 document also matched/
      assert_select "button[data-controller=clipboard][data-clipboard-text-value]"
      assert_select "time"
    end
    assert_select "textarea[name=question]:not([disabled])"
  end

  test "a streaming answer shows the latest step and locks the composer" do
    @conversation.messages.create!(role: "user", content: "Question")
    @conversation.messages.create!(role: "assistant", status: "streaming", content: "The car was",
      steps: [ { "label" => "Searching for “car”" }, { "label" => "Counting documents by year" } ])

    get conversation_path(@conversation)

    assert_select "article[data-message-status=streaming][aria-busy=true]" do
      assert_select "[data-research-status] .shimmer", text: "Counting documents by year"
      assert_select "details", count: 0
      assert_select ".prose-answer[data-streaming]", text: /The car was/
    end
    assert_select "textarea[name=question][disabled]"
    assert_select "button[data-chat-target=send][disabled]"
  end

  test "a streaming answer with no text yet shows one working indicator" do
    @conversation.messages.create!(role: "assistant", status: "streaming")

    get conversation_path(@conversation)

    assert_select "[data-research-status] .shimmer", text: "Thinking"
    assert_select "[data-research-status]", count: 1
    assert_select ".typing-dot", count: 0
  end

  test "a failed answer explains what happened" do
    @conversation.messages.create!(role: "assistant", status: "failed", content: "Research stopped: The server is overloaded.",
      steps: [ { "label" => "Searching for “car”" } ])

    get conversation_path(@conversation)

    assert_select "article[data-message-status=failed]" do
      assert_select "p", text: /Research stopped/
      assert_select "p", text: "The server is overloaded."
      assert_select "button", text: "Retry"
      assert_select "summary", text: /Stopped · 1 step/
      assert_select ".prose-answer", count: 0
    end
  end

  test "deleting asks with the custom confirm" do
    get conversation_path(@conversation)

    assert_select "form[data-turbo-confirm][data-turbo-confirm-button='Delete conversation']"
    delete conversation_path(@conversation)
    assert_redirected_to conversations_path
    assert_raises(ActiveRecord::RecordNotFound) { @conversation.reload }
  end

  test "the broadcast partial renders on its own" do
    message = @conversation.messages.create!(role: "assistant", status: "complete", content: "Done.", steps: [ { "label" => "Searching for “x”" } ])

    html = ApplicationController.render(partial: "messages/message", locals: { message: message })

    assert_includes html, %(id="message_#{message.id}")
    assert_includes html, "Researched · 1 step"
    assert_includes html, "Done."
  end
end
