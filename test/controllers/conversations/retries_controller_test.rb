require "test_helper"

class Conversations::RetriesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "retries a stopped answer" do
    conversation = Conversation.start!(user: users(:one), question: "Bills?")
    answer = conversation.messages.last
    answer.fail!("network down")

    get conversation_path(conversation)
    assert_select "form[action=?]", conversation_message_retry_path(conversation, answer)

    assert_enqueued_with(job: ResearchJob) { post conversation_message_retry_path(conversation, answer) }

    assert_redirected_to conversation_path(conversation)
    assert answer.reload.streaming?
  end
end
