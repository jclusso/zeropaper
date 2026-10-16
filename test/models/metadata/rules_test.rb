require "test_helper"

class Metadata::RulesTest < ActiveSupport::TestCase
  test "finds dates in common formats" do
    [ "Issued 2026-03-14", "Issued 03/14/2026", "Issued 14.03.2026", "Issued March 14th, 2026", "Issued 14 Mar 2026" ].each do |text|
      document = document_with_text(text)

      assert_equal Date.new(2026, 3, 14), Metadata::Rules.new(document).find_date, text
    end
  end

  test "uses the earliest plausible date" do
    document = document_with_text("Valid until 2099-01-01. Issued 2026-03-14. Paid 2026-04-02.")

    assert_equal Date.new(2026, 3, 14), Metadata::Rules.new(document).find_date
  end

  test "ignores impossible dates" do
    assert_nil Metadata::Rules.new(document_with_text("Ref 02/31/2026")).find_date
  end

  test "titles come from a meaningful filename" do
    document = document_with_text("whatever", filename: "electricity_bill_march.pdf")

    assert_equal "electricity bill march", Metadata::Rules.new(document).find_title
  end

  test "titles come from the text when the filename is a scanner's" do
    document = document_with_text("\n12\nElectricity statement for March\nAmount due", filename: "scan_0001.pdf")

    assert_equal "Electricity statement for March", Metadata::Rules.new(document).find_title
  end

  test "applies matching taxonomy" do
    document = document_with_text(BILL_TEXT, filename: "scan_0001.pdf")

    Metadata::Rules.new(document).apply

    assert_equal correspondents(:acme_power), document.correspondent
    assert_equal document_types(:invoice), document.document_type
    assert_equal [ tags(:utilities) ], document.tags.to_a
    assert_equal Date.new(2026, 3, 14), document.document_date
    assert_equal "rules", document.metadata_source
  end

  test "keeps manually entered details and fills the gaps" do
    document = document_with_text(BILL_TEXT, title: "Power, March", metadata_source: "manual")

    Metadata::Rules.new(document).apply

    assert_equal "Power, March", document.title
    assert_equal correspondents(:acme_power), document.correspondent
    assert_equal "manual", document.metadata_source
  end
end
