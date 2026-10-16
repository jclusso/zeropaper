require "test_helper"

class DocumentTitleTest < ActiveSupport::TestCase
  MARCH_26 = Date.new(2026, 3, 26)

  test "the same document titled two ways comes out the same" do
    assert_equal "BMW X5 M Service Invoice", DocumentTitle.clean("BMW X5 M service invoice March 2026", date: MARCH_26)
    assert_equal "BMW X5 M Service Invoice", DocumentTitle.clean("BMW X5 M service invoice", date: MARCH_26)
  end

  test "a trailing date matching the document date is dropped, in any common format" do
    assert_equal "Receipt", DocumentTitle.clean("Receipt - March 26, 2026", date: MARCH_26)
    assert_equal "Receipt", DocumentTitle.clean("Receipt 2026-03-26", date: MARCH_26)
    assert_equal "Statement", DocumentTitle.clean("Statement for 2026-03", date: MARCH_26)
    assert_equal "Water Bill", DocumentTitle.clean("water bill for March 2026", date: Date.new(2026, 3, 2))
  end

  test "dates that are part of the identity stay" do
    assert_equal "2025 Tax Return", DocumentTitle.clean("2025 tax return", date: MARCH_26)
    assert_equal "Receipt March 2025", DocumentTitle.clean("receipt March 2025", date: MARCH_26)
  end

  test "title case keeps acronyms and model names and lowercases small words" do
    assert_equal "Letter from the IRS About a Refund", DocumentTitle.title_case("letter from the IRS about a refund")
    assert_equal "iPhone 15 Pro Receipt", DocumentTitle.title_case("iPhone 15 Pro receipt")
    assert_equal "Notice of Lease Payoff for 2022 BMW X5 M", DocumentTitle.title_case("notice of lease payoff for 2022 BMW X5 M")
  end

  test "all-caps titles are cased, keeping short acronyms" do
    assert_equal "Payroll Summary", DocumentTitle.title_case("PAYROLL SUMMARY")
    assert_equal "IRS Notice of Change", DocumentTitle.title_case("IRS NOTICE OF CHANGE")
  end
end
