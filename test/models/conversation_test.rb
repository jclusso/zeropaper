require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  test "starting a conversation asks the first question" do
    conversation = nil
    assert_enqueued_with(job: ResearchJob) do
      conversation = Conversation.start!(user: users(:one), question: "  What did I pay for electricity in 2026?  ")
    end

    assert_equal "What did I pay for electricity in 2026?", conversation.title
    assert_equal %w[user assistant], conversation.messages.map(&:role)
    assert conversation.busy?
  end

  test "a blank question is refused" do
    conversation = users(:one).conversations.create!(title: "Empty")

    assert_raises(ArgumentError) { conversation.ask!(" ") }
    assert_empty conversation.messages
  end

  test "finishing an answer keeps citations and private matches" do
    conversation = Conversation.start!(user: users(:one), question: "Bills?")
    answer = conversation.messages.last

    answer.finish!(content: "It was $87.40 [#1].", cited_document_ids: [ 1 ], private_match_ids: [ 2 ])

    assert_equal "complete", answer.reload.status
    assert_equal [ 1 ], answer.cited_document_ids
    assert_equal [ 2 ], answer.private_match_ids
    refute conversation.busy?
  end
end
