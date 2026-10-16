require "test_helper"
require "turbo/broadcastable/test_helper"

class Document::BroadcastingTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  BROADCAST_JOBS = [ Turbo::Streams::BroadcastStreamJob, Turbo::Streams::ActionBroadcastJob ].freeze

  test "a new document refreshes pages listing documents" do
    refreshes = broadcasts_to(Document::LIBRARY_STREAM) { ingest(BILL_TEXT, filename: "bill.txt") }

    assert_includes refreshes.map { |stream| stream["action"] }, "refresh"
  end

  test "processing steps saved without callbacks still refresh pages listing documents" do
    document = ingest(BILL_TEXT, filename: "bill.txt")

    refreshes = broadcasts_to(Document::LIBRARY_STREAM) { document.send(:record_step, "ocr", "done") }

    assert_includes refreshes.map { |stream| stream["action"] }, "refresh"
  end

  test "the inbox count follows documents entering and leaving the inbox" do
    document = ingest(BILL_TEXT, filename: "bill.txt")
    count = Document.in_inbox.count

    added = broadcasts_to(Document::INBOX_COUNT_STREAM) { document.add_review_reason!("blank_pages") }
    assert_equal [ "replace" ], added.map { |stream| stream["action"] }
    assert_equal "inbox_count", added.first["target"]
    assert_equal (count + 1).to_s, added.first.at_css("#inbox_count").text

    removed = broadcasts_to(Document::INBOX_COUNT_STREAM) { document.destroy! }
    assert_equal count.to_s, removed.last.at_css("#inbox_count").text
  end

  test "the inbox count is hidden when the inbox is empty" do
    Document.update_all(needs_review: false)

    badge = Nokogiri::HTML5.fragment(ApplicationController.render(partial: "layouts/inbox_count")).at_css("#inbox_count")

    assert badge.key?("hidden")
    assert_equal "0", badge.text
  end

  private
    def broadcasts_to(stream, &block)
      capture_turbo_stream_broadcasts(stream) { perform_enqueued_jobs(only: BROADCAST_JOBS, &block) }
    end
end
