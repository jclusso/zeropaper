require "test_helper"

class Search::QueryParserTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 10, 16)

  test "a correspondent, a type and a season become filters" do
    parsed = parse("invoices from Acme Power last spring")

    assert_equal "", parsed.keywords
    assert_equal correspondents(:acme_power).id, parsed.filters[:correspondent_id]
    assert_equal [ document_types(:invoice).id ], parsed.filters[:document_type_ids]
    assert_equal [ "2026-03-01", "2026-05-31" ], parsed.filters.values_at(:date_from, :date_to)
    assert_equal [ "Last spring", "From: Acme Power", "Type: Invoice" ], parsed.chips.map(&:label)
  end

  test "remaining words are searched" do
    parsed = parse("water heater warranty 2025")

    assert_equal "water heater warranty", parsed.keywords
    assert_equal [ "2025-01-01", "2025-12-31" ], parsed.filters.values_at(:date_from, :date_to)
  end

  test "date phrases" do
    assert_equal [ "2025-03-01", "2025-03-31" ], dates("March 2025")
    assert_equal [ "2026-03-01", "2026-03-31" ], dates("march")
    assert_equal [ "2025-11-01", "2025-11-30" ], dates("november")
    assert_equal [ "2025-01-01", "2025-12-31" ], dates("last year")
    assert_equal [ "2026-10-01", "2026-10-16" ], dates("this month")
    assert_equal [ "2026-09-16", "2026-10-16" ], dates("last 30 days")
    assert_equal [ "2024-12-01", "2025-02-28" ], dates("winter 2025")
    assert_equal [ "2025-12-01", "2026-02-28" ], dates("last winter")
    assert_equal [ nil, "2023-12-31" ], dates("before 2024")
    assert_equal [ "2023-06-01", nil ], dates("since June 2023")
  end

  test "tags need a # or the word tagged" do
    assert_nil parse("utilities bill").filters[:tag_ids]
    assert_equal [ tags(:utilities).id ], parse("bill #utilities").filters[:tag_ids]
    assert_equal [ tags(:utilities).id ], parse("bills tagged utilities").filters[:tag_ids]
  end

  test "every tag in the query becomes a filter" do
    parsed = parse("bill #utilities #taxes")

    assert_equal [ tags(:taxes).id, tags(:utilities).id ].sort, parsed.filters[:tag_ids].sort
    assert_equal "bill", parsed.keywords
  end

  test "names match whole words only" do
    assert_nil parse("acmes and invoiced").filters[:correspondent_id]
    assert_nil parse("invoiced").filters[:document_type_ids]
  end

  test "literal phrases stay words" do
    parsed = parse("from Acme Power 2025", literal: [ "from Acme Power" ])

    assert_nil parsed.filters[:correspondent_id]
    assert_equal "from Acme Power", parsed.keywords
    assert_equal [ "2025" ], parsed.chips.map(&:label)
  end

  private
    def parse(query, literal: [])
      Search::QueryParser.new(query, literal: literal, today: TODAY).call
    end

    def dates(query)
      parse(query).filters.values_at(:date_from, :date_to)
    end
end
