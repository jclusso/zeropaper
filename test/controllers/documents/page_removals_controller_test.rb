require "test_helper"

class Documents::PageRemovalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @document = process(ingest(scanned_pdf(PdfFactory.printed, PdfFactory.blank, PdfFactory.printed), filename: "scan.pdf"))
    assert_equal [ 2 ], @document.suggested_blank_pages
  end

  test "keeping every suggested page marks them not blank and reads them" do
    assert_enqueued_with(job: ProcessDocumentJob, args: [ @document, { extract_metadata: false } ]) do
      post document_page_removal_path(@document)
    end

    assert_redirected_to @document
    assert_equal "Kept 1 page marked blank.", flash[:notice]
    @document.reload
    assert_equal 3, @document.page_count
    assert_empty @document.suggested_blank_pages
    refute_includes @document.review_reasons, "blank_pages"
  end

  test "removing pages still works and reports what happened" do
    post document_page_removal_path(@document), params: { pages: [ 2 ] }

    assert_redirected_to @document
    assert_equal "Removed 1 page.", flash[:notice]
    assert_equal 2, @document.reload.page_count
  end

  test "the dialog offers to keep pages when none are selected" do
    get document_pages_path(@document)

    assert_select "[data-page-selection-suggested-value='1']"
    assert_select "[data-page-selection-target=keepIcon]"
  end

  test "the review bar offers Not blank" do
    get document_path(@document)

    assert_select "form[action='#{document_page_removal_path(@document)}'] button", text: "Not blank"
  end
end
