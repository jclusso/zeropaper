require "test_helper"

class TextOverlapTest < ActiveSupport::TestCase
  test "two scans of the same report are duplicates" do
    report = format(INSPECTION_REPORT, date: "3/27/2026", expires: "03/31/2027", model: "M240i", vin: "WBA2J5C50KVB12345", miles: "18422")
    rescan = report.sub("Brakes passed", "Brakes  passed").sub("M240i", "M240i,")

    overlap = TextOverlap.new(report, rescan)

    assert overlap.duplicate?
    assert_operator overlap.text_score, :>=, 0.9
  end

  test "reports from the same template for other cars are not duplicates" do
    one = format(INSPECTION_REPORT, date: "3/27/2026", expires: "03/31/2027", model: "M240i", vin: "WBA2J5C50KVB12345", miles: "18422")
    other = format(INSPECTION_REPORT, date: "4/23/2025", expires: "04/30/2026", model: "X5", vin: "5YMJU0C08R9T67890", miles: "30115")

    overlap = TextOverlap.new(one, other)

    refute overlap.duplicate?
    assert_operator overlap.number_score, :<, 0.3
  end

  test "different letters are not duplicates" do
    refute TextOverlap.new("Your refund has been issued for order 1234.", "Please renew your library card before May.").duplicate?
  end

  test "empty text scores zero" do
    assert_equal 0.0, TextOverlap.new("", "Anything").text_score
  end
end
