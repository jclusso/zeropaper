require "test_helper"

class Documents::ProcessingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @document = document_with_text("Lease payoff letter", status: "processing")
  end

  test "stop ends processing" do
    delete document_processing_path(@document)

    assert_redirected_to @document
    assert_equal "failed", @document.reload.status
  end

  test "restart queues a fresh run while one is in progress" do
    assert_enqueued_with(job: ProcessDocumentJob) do
      post document_reprocessing_path(@document)
    end

    assert_redirected_to @document
    assert_equal "Restarted processing.", flash[:notice]
    assert_equal "pending", @document.reload.status
  end

  test "a processing document offers stop and restart, without a header badge" do
    @document.update_columns(steps: { "inspect" => { "status" => "done" }, "text" => { "status" => "running" } })

    get document_path(@document)

    assert_select "form[action='#{document_processing_path(@document)}'] button", text: "Stop"
    assert_select "form[action='#{document_reprocessing_path(@document)}'] button", text: "Restart"
    assert_select ".badge-accent", text: /Processing/, count: 0
  end
end
