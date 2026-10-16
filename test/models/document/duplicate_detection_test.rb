require "test_helper"

class Document::DuplicateDetectionTest < ActiveSupport::TestCase
  test "a rescan of the same report is flagged as its duplicate" do
    original = report_document(model: "M240i", vin: "WBA2J5C50KVB12345", date: "3/27/2026")
    copy = report_document(model: "M240i", vin: "WBA2J5C50KVB12345", date: "3/27/2026")

    copy.send(:flag_possible_duplicate)

    assert_equal original, copy.reload.duplicate_of
    assert_includes copy.review_reasons, "possible_duplicate"
  end

  test "a report from the same template for another car is not flagged" do
    report_document(model: "X5", vin: "5YMJU0C08R9T67890", date: "4/23/2025")
    other = report_document(model: "M240i", vin: "WBA2J5C50KVB12345", date: "3/27/2026")

    other.send(:flag_possible_duplicate)

    assert_nil other.reload.duplicate_of
    refute_includes other.review_reasons, "possible_duplicate"
  end

  private
    def report_document(model:, vin:, date:)
      text = format(INSPECTION_REPORT, date: date, expires: date.sub(/\d{4}\z/) { |year| (year.to_i + 1).to_s }, model: model, vin: vin, miles: vin.last(5))
      document_with_text(text, title: "BMW #{model} Vehicle Inspection Report").tap(&:index!)
    end
end
