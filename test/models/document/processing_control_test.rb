require "test_helper"

class Document::ProcessingControlTest < ActiveSupport::TestCase
  test "a document left processing with no live job is marked failed" do
    stuck = document_with_text("Lease payoff letter", status: "processing")
    stuck.update_columns(updated_at: 20.minutes.ago)
    recent = document_with_text("Still going", status: "processing")

    Document.recover_stuck

    assert_equal "failed", stuck.reload.status
    assert_equal Document::Processing::STUCK_MESSAGE, stuck.error
    assert_includes stuck.review_reasons, "failed"
    assert_equal "processing", recent.reload.status
  end

  test "a document with a live queued job is left alone" do
    waiting = document_with_text("Queued behind others", status: "pending")
    waiting.update_columns(updated_at: 20.minutes.ago)
    SolidQueue::Job.create!(queue_name: "default", class_name: "ProcessDocumentJob",
      arguments: ProcessDocumentJob.new(waiting).serialize)

    assert waiting.processing_job_alive?
    Document.recover_stuck

    assert_equal "pending", waiting.reload.status
  end

  test "stopping marks the document failed so it can be retried" do
    document = document_with_text("Processing", status: "processing")

    document.stop_processing!

    assert_equal "failed", document.reload.status
    assert_equal "Stopped before it finished.", document.error
    refute document.processing?
  end

  test "a run that was restarted gives up at its next step" do
    document = ingest(BILL_TEXT, filename: "bill.txt")
    document.stubs(:inspect_file).with { document.process_later; true }.returns("1 page")

    document.process!

    document.reload
    assert_equal "pending", document.status, "the newer run owns the document"
    assert_nil document.step_state("text")["status"], "the old run stopped before reading text"
  end

  test "turning pages upright can be switched off" do
    Setting.instance.update!(auto_rotate_pages: false)
    Orientation.expects(:pdf_rotations).never

    document = process(ingest(scanned_text_pdf("PAYROLL SUMMARY\nEmployee salary report\n"), filename: "scan_0006.pdf"))

    assert_equal "skipped", document.step_state("orientation")["status"]
  end

  test "external commands are stopped when they run too long" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    error = assert_raises(Pdf::CommandFailed) { Pdf.capture("sleep", "5", timeout: 0.5) }

    assert_match "did not finish", error.message
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 4
  end
end
