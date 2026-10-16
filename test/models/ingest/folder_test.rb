require "test_helper"

class Ingest::FolderTest < ActiveSupport::TestCase
  setup do
    @root = Pathname(Dir.mktmpdir)
    @folder = Ingest::Folder.new(@root)
    @folder.prepare
  end

  teardown { FileUtils.rm_rf(@root) }

  test "ingests settled files and removes them" do
    settled_file("statement.txt", BILL_TEXT)

    assert_difference -> { Document.count } do
      @folder.scan
    end

    document = Document.last
    assert_equal "folder", document.source
    assert_equal "statement.txt", document.source_detail
    refute document.private?
    refute @root.join("statement.txt").exist?
  end

  test "files in the private folder are private from the start" do
    settled_file("private/diagnosis.txt", "Diagnosis letter")

    @folder.scan

    document = Document.last
    assert document.private?
    assert_equal "Added from the private folder", document.private_reason
  end

  test "files still being written and hidden files are left alone" do
    @root.join("fresh.txt").write("still copying")
    settled_file(".DS_Store", "junk")

    assert_no_difference -> { Document.count } do
      @folder.scan
    end
    assert @root.join("fresh.txt").exist?
  end

  test "unsupported files move aside and duplicates are removed" do
    settled_file("archive.exe", "MZ binary")
    settled_file("statement.txt", BILL_TEXT)
    @folder.scan
    settled_file("again.txt", BILL_TEXT)

    assert_no_difference -> { Document.count } do
      @folder.scan
    end
    assert @root.join(".unsupported/archive.exe").exist?
    refute @root.join("again.txt").exist?
  end

  private
    def settled_file(relative, content)
      path = @root.join(relative)
      FileUtils.mkdir_p(path.dirname)
      path.write(content)
      File.utime(1.minute.ago.to_time, 1.minute.ago.to_time, path)
    end
end
