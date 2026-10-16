require "test_helper"

class Document::PagesTest < ActiveSupport::TestCase
  setup do
    @pdf = scanned_pdf(PdfFactory.printed, PdfFactory.blank, PdfFactory.printed)
    @document = process(ingest(@pdf, filename: "scan.pdf"))
  end

  test "processing records the blank page and skips it in OCR" do
    assert_equal 3, @document.page_count
    assert_equal [ 2 ], @document.suggested_blank_pages
    assert_equal [ 2 ], @document.page_record["ocr_skipped"]
    assert_equal [ 1, 3 ], @document.pages_to_read
    assert_includes @document.review_reasons, "blank_pages"
  end

  test "removing a page OCR skipped keeps the text and does not reprocess" do
    original_checksum = @document.checksum

    assert_no_enqueued_jobs(only: ProcessDocumentJob) { @document.remove_pages!([ 2 ]) }

    @document.reload
    assert_equal 2, @document.page_count
    assert_equal [ 1, 3 ], @document.page_map
    assert_empty @document.suggested_blank_pages
    refute_equal original_checksum, @document.checksum
    assert @document.original_file.attached?
    assert_equal @pdf, @document.original_file.download
    @document.with_file_copy { |path| assert_equal 2, Pdf.page_count(path) }
    refute_includes @document.review_reasons, "blank_pages"
  end

  test "removing a page that was read queues OCR again without new details" do
    assert_enqueued_with(job: ProcessDocumentJob, args: [ @document, { extract_metadata: false } ]) do
      @document.remove_pages!([ 1 ])
    end

    assert_equal [ 2, 3 ], @document.reload.page_map
  end

  test "keeping a page found blank confirms it and reads it" do
    assert_enqueued_with(job: ProcessDocumentJob) { @document.remove_pages!([], keep_blank: [ 2 ]) }

    @document.reload
    assert_equal [ 2 ], @document.page_record["confirmed"]
    assert_empty @document.suggested_blank_pages
    assert_equal 3, @document.page_count
  end

  test "page numbers stay tied to the original after earlier pages go" do
    @document.remove_pages!([ 1 ])
    @document.reload

    assert_equal 2, @document.original_page_number(1)
    assert_equal 1, @document.current_page_number(2)
    assert_equal [ 1 ], @document.suggested_blank_pages
  end

  test "refuses to remove every page" do
    assert_raises(Document::Pages::EditRefused) { @document.remove_pages!([ 1, 2, 3 ]) }
    assert_equal 3, @document.reload.page_count
  end

  test "refuses while the document is processing" do
    @document.update!(status: "processing")

    assert_raises(Document::Pages::EditRefused) { @document.remove_pages!([ 2 ]) }
  end

  test "restore_original! brings the upload back" do
    original_checksum = @document.checksum
    @document.remove_pages!([ 2 ])

    assert_enqueued_with(job: ProcessDocumentJob) { @document.reload.restore_original! }

    @document.reload
    assert_equal original_checksum, @document.checksum
    assert_equal @pdf, @document.file.download
    refute @document.original_file.attached?
  end

  test "restore_original! needs an original" do
    assert_raises(Document::Pages::EditRefused) { @document.restore_original! }
  end
end
