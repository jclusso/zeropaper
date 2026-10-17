require "test_helper"

class Document::IndexWaitingTest < ActiveSupport::TestCase
  setup do
    configure_openai
    Embedder.stubs(:downloaded?).returns(false)
    Embedder.stubs(:embed_documents).raises(Embedder::ModelMissing, "The search model has not finished downloading.")
  end

  test "a document processed before the search model downloads is ready, found by keyword, and waits for its passages" do
    document = processed_bill

    assert_equal "ready", document.status
    assert_equal "waiting", document.step_state("index")["status"]
    assert_equal Document::INDEX_WAITING_NOTE, document.step_state("index")["detail"]
    refute_includes document.review_reasons, "failed"
    assert_empty document.chunks
    assert_includes Search.new(query: "electricity statement").results, document
    assert_equal [ document ], Document.waiting_for_index.to_a
  end

  test "once the model downloads, a waiting document is indexed without being read or sent again" do
    document = processed_bill
    model_ready
    Metadata::AI.any_instance.expects(:apply).never
    Ocr::AI.any_instance.expects(:call).never
    WebMock::RequestRegistry.instance.reset!

    assert_no_enqueued_jobs(only: ProcessDocumentJob) do
      perform_enqueued_jobs(only: IndexDocumentJob) { DownloadEmbeddingModelJob.perform_now }
    end

    document.reload
    assert_equal "done", document.step_state("index")["status"]
    assert document.chunks.any?
    assert_not_nil document.embedding
    assert_empty Document.waiting_for_index
    assert_no_external_requests
  end

  test "a document still being processed is left to its run" do
    document = processed_bill
    model_ready
    document.update_columns(status: "pending")

    assert_no_enqueued_jobs(only: IndexDocumentJob) { DownloadEmbeddingModelJob.perform_now }
  end

  test "a document that finds the model missing just after the download finished is indexed anyway" do
    Embedder.stubs(:downloaded?).returns(true)

    assert_enqueued_jobs(1, only: IndexDocumentJob) { processed_bill }
  end

  private
    def processed_bill
      Metadata::AI.any_instance.stubs(:apply)
      process(ingest(DocumentHelpers::BILL_TEXT, filename: "statement.txt"))
    ensure
      Metadata::AI.any_instance.unstub(:apply)
    end

    def model_ready
      Embedder.unstub(:embed_documents)
      Embedder.stubs(:downloaded?).returns(true)
    end
end
