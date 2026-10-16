require "test_helper"

class Document::IngestibleTest < ActiveSupport::TestCase
  test "stores the file and queues processing" do
    document = ingest(BILL_TEXT, filename: "bill.txt", uploaded_by: users(:one))

    assert_equal "text/plain", document.content_type
    assert_equal Digest::SHA256.hexdigest(BILL_TEXT), document.checksum
    assert_equal "pending", document.status
    assert_equal users(:one), document.uploaded_by
    assert_equal BILL_TEXT, document.file.download
  end

  test "detects PDFs by content" do
    document = ingest(text_pdf("Hello"), filename: "letter.pdf")

    assert_equal "application/pdf", document.content_type
  end

  test "refuses the same bytes twice" do
    first = ingest(BILL_TEXT, filename: "bill.txt")

    error = assert_raises(Document::Ingestible::Duplicate) do
      Document.ingest!(io: StringIO.new(BILL_TEXT), filename: "copy.txt", source: "upload")
    end
    assert_equal first, error.document
    assert_equal 1, Document.count
  end

  test "refuses unsupported files" do
    assert_raises(Document::Ingestible::UnsupportedType) do
      Document.ingest!(io: StringIO.new("\x00\x01binary".b * 50), filename: "program.exe", source: "upload")
    end
    assert_equal 0, Document.count
  end

  test "keeps the reason a document is private" do
    document = ingest(BILL_TEXT, filename: "bill.txt", source: "folder", private: true, private_reason: "Added from the private folder")

    assert document.private?
    assert_equal "Added from the private folder", document.private_reason
    assert_equal "folder", document.source
  end

  test "a source rule marks folder documents private at ingest" do
    Rule.create!(name: "Folder is private", conditions: [ { field: "source", operator: "is", value: "folder" } ], mark_private: true)

    assert ingest(BILL_TEXT, filename: "statement.txt", source: "folder").private?
    refute ingest("Something else", filename: "other.txt", source: "upload").private?
  end
end
