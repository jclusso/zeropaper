require "test_helper"

class Document::SpreadsheetTest < ActiveSupport::TestCase
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @document = ingest("Date,Amount\n2026-03-14,87.40\n", filename: "payments.csv")
  end

  teardown { Rails.cache = @original_cache }

  test "parses the sheets once and serves later views from the cache" do
    first = @document.spreadsheet_sheets
    NativeText.expects(:sheets).never
    second = Document.find(@document.id).spreadsheet_sheets

    assert_equal [ [ "Date", "Amount" ], [ "2026-03-14", "87.40" ] ], first.first[:rows]
    assert_equal first, second
    refute_includes Rails.cache.read([ "spreadsheet-sheets", @document.file.blob.key ]), "87.40"
  end

  test "a replaced file is parsed again" do
    @document.spreadsheet_sheets
    @document.update!(file: { io: StringIO.new("Date,Amount\n2026-04-14,90.10\n"), filename: "payments.csv", content_type: "text/csv" })

    assert_equal [ "2026-04-14", "90.10" ], @document.reload.spreadsheet_sheets.first[:rows].last
  end

  test "keeps only the rows the viewer shows" do
    rows = Array.new(Document::SPREADSHEET_VIEW_ROWS + 5) { |i| "row #{i}" }
    NativeText.stubs(:sheets).returns([ { name: "Sheet1", rows: rows.map { |row| [ row ] } } ])

    assert_equal Document::SPREADSHEET_VIEW_ROWS, @document.spreadsheet_sheets.first[:rows].size
  end
end
