require "test_helper"

class UploadLimitTest < ActiveSupport::TestCase
  setup { Rails.configuration.x.stubs(:max_upload_bytes).returns(1.megabyte) }

  test "uploads default to 250 MB" do
    Rails.configuration.x.unstub(:max_upload_bytes)

    assert_equal 250.megabytes, UploadLimit.max_bytes
    assert_equal 1_000.megabytes, UploadLimit.max_expanded_bytes
  end

  test "a file over the limit is refused before it is read" do
    error = assert_raises(Document::TooLarge) do
      Document.ingest!(io: StringIO.new("x" * (1.megabyte + 1)), filename: "big.txt", source: "upload")
    end

    assert_match "1 MB upload limit", error.message
    assert_equal 0, Document.count
  end

  test "a file at the limit is accepted" do
    document = ingest("x" * 1.megabyte, filename: "big.txt")

    assert_equal 1.megabyte, document.file.byte_size
  end

  test "a Word file that unzips past four times the limit is not parsed" do
    with_zip("word/document.xml" => "0" * 5.megabytes) do |path|
      Docx::Document.expects(:open).never

      error = assert_raises(UploadLimit::Exceeded) { NativeText.extract(path, NativeText::WORD_TYPE) }
      assert_match "4 MB limit", error.message
    end
  end

  test "a spreadsheet that unzips past four times the limit is not parsed" do
    with_zip("xl/worksheets/sheet1.xml" => "0" * 5.megabytes) do |path|
      Roo::Spreadsheet.expects(:open).never

      assert_raises(UploadLimit::Exceeded) { NativeText.extract(path, NativeText::SPREADSHEET_TYPES.first) }
    end
  end

  test "a restore archive with an entry that unzips past the limit is refused" do
    with_zip("manifest.json" => "{}", "documents/1/file/bomb.txt" => "0" * 5.megabytes) do |path|
      assert_raises(UploadLimit::Exceeded) { Archive::Reader.new(path).each_result { } }
    end
    assert_equal 0, Document.count
  end

  test "spreadsheets are read up to the row limit" do
    Tempfile.create([ "rows", ".csv" ]) do |file|
      file.write(Array.new(NativeText::MAX_ROWS + 10) { |index| "row #{index},value\n" }.join)
      file.flush

      rows = NativeText.sheets(file.path, "text/csv").sole[:rows]
      assert_equal NativeText::MAX_ROWS, rows.size
      assert_equal [ "row 0", "value" ], rows.first
    end
  end

  private
    def with_zip(entries)
      Tempfile.create([ "bomb", ".zip" ]) do |file|
        Zip::OutputStream.open(file.path) do |zip|
          entries.each do |name, content|
            zip.put_next_entry(name)
            zip.write(content)
          end
        end
        assert_operator File.size(file.path), :<, 1.megabyte, "the zip itself is small"
        yield file.path
      end
    end
end
