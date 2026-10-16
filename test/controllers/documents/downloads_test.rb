require "test_helper"

class Documents::DownloadsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "a scan downloads as its searchable PDF, with the upload in the menu" do
    Setting.instance.update!(searchable_pdf: true)
    scan = scanned_text_pdf("PAYROLL SUMMARY\nEmployee salary report\n")
    document = process(ingest(scan, filename: "scan_0007.pdf"))
    assert document.archive_file.attached?

    get document_file_path(document, variant: "best", download: 1)
    assert_response :success
    assert_equal document.archive_file.download, response.body
    assert_match "attachment", response.headers["Content-Disposition"]

    get document_file_path(document, variant: "upload", download: 1)
    assert_equal scan, response.body

    get document_path(document)
    assert_select "a[href='#{document_file_path(document, variant: "best", download: 1)}']"
    assert_select "el-menu a[href='#{document_file_path(document, variant: "upload", download: 1)}']", text: /Original upload/
    assert_select "a", text: "Searchable PDF", count: 0
  end

  test "a born-digital PDF has one download and no menu" do
    document = process(ingest(text_pdf("Acme Power statement for March 2026 with the amount due of $87.40 by April 1"), filename: "statement.pdf"))

    get document_file_path(document, variant: "best", download: 1)
    assert_equal document.file.download, response.body

    get document_path(document)
    assert_select "[aria-label='More download options']", count: 0
  end

  test "after pages are removed the upload is offered as it was" do
    document = process(ingest(scanned_pdf(PdfFactory.printed, PdfFactory.blank, PdfFactory.printed), filename: "scan.pdf"))
    upload = document.file.download
    document.remove_pages!([ 2 ])

    get document_file_path(document, variant: "upload", download: 1)
    assert_equal upload, response.body
  end
end
