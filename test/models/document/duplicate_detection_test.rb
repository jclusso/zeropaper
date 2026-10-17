require "test_helper"

class Document::DuplicateDetectionTest < ActiveSupport::TestCase
  test "a rescan of the same report is flagged as its duplicate" do
    original = report_document(model: "M240i", vin: "WBA2J5C50KVB12345", date: "3/27/2026")
    copy = report_document(model: "M240i", vin: "WBA2J5C50KVB12345", date: "3/27/2026")

    copy.flag_possible_duplicate

    assert_equal original, copy.reload.duplicate_of
    assert_includes copy.review_reasons, "possible_duplicate"
  end

  test "a report from the same template for another car is not flagged" do
    report_document(model: "X5", vin: "5YMJU0C08R9T67890", date: "4/23/2025")
    other = report_document(model: "M240i", vin: "WBA2J5C50KVB12345", date: "3/27/2026")

    other.flag_possible_duplicate

    assert_nil other.reload.duplicate_of
    refute_includes other.review_reasons, "possible_duplicate"
  end

  test "a rescan OCR read differently is flagged when its pages and numbers match" do
    page = PageHash.of(PdfFactory.printed.to_gray)
    original = report_document(model: "M240i", vin: "WBA2J5C50KVB12345", date: "3/27/2026", page_hashes: [ page ])
    copy = report_document(model: "M240i", vin: "WBA2J5C50KVB12345", date: "3/27/2026", misread: true, page_hashes: [ page ])
    copy.update_columns(embedding: original.embedding)
    assert_operator TextOverlap.new(copy.content, original.content).text_score, :<, TextOverlap::DUPLICATE_TEXT

    copy.flag_possible_duplicate

    assert_equal original, copy.reload.duplicate_of
  end

  test "a report from the same template that looks the same is not flagged when its numbers differ" do
    page = PageHash.of(PdfFactory.printed.to_gray)
    original = report_document(model: "X5", vin: "5YMJU0C08R9T67890", date: "4/23/2025", page_hashes: [ page ])
    other = report_document(model: "M240i", vin: "WBA2J5C50KVB12345", date: "3/27/2026", misread: true, page_hashes: [ page ])
    other.update_columns(embedding: original.embedding)

    other.flag_possible_duplicate

    assert_nil other.reload.duplicate_of
  end

  private
    # misread garbles words the way OCR does on a second scan, leaving the
    # numbers alone.
    def report_document(model:, vin:, date:, misread: false, **attributes)
      text = format(INSPECTION_REPORT, date: date, expires: date.sub(/\d{4}\z/) { |year| (year.to_i + 1).to_s }, model: model, vin: vin, miles: vin.last(5))
      text = text.gsub("passed", "pa ssed").gsub("Inspection", "Inspectlon") if misread
      document_with_text(text, title: "BMW #{model} Vehicle Inspection Report", **attributes).tap(&:index!)
    end
end
