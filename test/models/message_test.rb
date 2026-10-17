require "test_helper"

class MessageTest < ActiveSupport::TestCase
  setup do
    @conversation = Conversation.start!(user: users(:one), question: "What did I pay for electricity?")
    @answer = @conversation.messages.last
  end

  test "an answer left streaming with no live job is failed so the conversation can go on" do
    @answer.update_columns(content: "Half an ans", updated_at: 20.minutes.ago)
    clear_enqueued_jobs

    Message.recover_stuck

    assert_equal "failed", @answer.reload.status
    assert_includes @answer.content, Message::STUCK_MESSAGE
    refute @conversation.busy?
    assert @answer.retryable?
  end

  test "an answer whose job is still queued is left alone" do
    @answer.update_columns(updated_at: 20.minutes.ago)
    SolidQueue::Job.enqueue(ResearchJob.new(@answer))

    Message.recover_stuck

    assert_equal "streaming", @answer.reload.status
  end

  test "retrying starts the answer again from nothing" do
    @answer.fail!("network down")

    assert_enqueued_with(job: ResearchJob, args: [ @answer ]) { @answer.retry! }

    @answer.reload
    assert_equal "streaming", @answer.status
    assert_equal "", @answer.content
  end

  test "only the latest stopped answer can be retried" do
    @answer.finish!(content: "It was $87.40.", cited_document_ids: [], private_match_ids: [])

    assert_raises(Message::NotRetryable) { @answer.retry! }
  end

  test "a rerun job clears earlier partial output and a finished answer is not run again" do
    @answer.update_columns(content: "Partial text from a worker that died")
    Research.any_instance.expects(:run).once.with { @answer.content.empty? }

    @answer.research!
    @answer.update_columns(status: "complete")
    @answer.research!

    assert_equal "", @answer.reload.content
  end
end
