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

  test "an older answer without full provenance carries every document used before it" do
    conversation = users(:one).conversations.create!(title: "Old")
    clinic = document_with_text("Clinic letter")
    water = document_with_text("Water bill")
    turns = [
      conversation.messages.create!(role: "user", content: "Clinic?"),
      conversation.messages.create!(role: "assistant", content: "Cardiology [##{clinic.id}].", cited_document_ids: [ clinic.id ]),
      conversation.messages.create!(role: "user", content: "Water?"),
      conversation.messages.create!(role: "assistant", content: "$41.20.", used_document_ids: [ water.id ])
    ]
    latest = conversation.messages.create!(role: "user", content: "Anything else?")

    history = conversation.shareable_history(before: latest, limit: 20)
    assert_equal turns, history.messages
    assert_equal [ clinic.id, water.id ].sort, history.document_ids.sort

    clinic.update!(private: true)
    assert_empty conversation.shareable_history(before: latest, limit: 20).messages, "the water answer may lean on the clinic answer"
  end

  test "an older answer that recorded no documents is left out, with the older answers after it" do
    conversation = users(:one).conversations.create!(title: "Old")
    water = document_with_text("Water bill")
    conversation.messages.create!(role: "user", content: "What did the clinic say?")
    conversation.messages.create!(role: "assistant", content: "It referred you to cardiology.")
    conversation.messages.create!(role: "user", content: "And the water bill?")
    conversation.messages.create!(role: "assistant", content: "$41.20.", used_document_ids: [ water.id ])
    recent = [
      conversation.messages.create!(role: "user", content: "Thanks"),
      conversation.messages.create!(role: "assistant", content: "You're welcome.", provenance_complete: true)
    ]
    latest = conversation.messages.create!(role: "user", content: "Anything else?")

    history = conversation.shareable_history(before: latest, limit: 20)

    assert_equal recent, history.messages
    assert_empty history.document_ids
  end
end
