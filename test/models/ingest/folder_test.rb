require "test_helper"

class Ingest::FolderTest < ActiveSupport::TestCase
  setup do
    @root = Pathname(Dir.mktmpdir)
    @folder = Ingest::Folder.new(@root)
    @folder.prepare
    Ingest::Folder::UNQUARANTINED.clear
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

  test "a copy of a stored document dropped in the private folder makes it private" do
    settled_file("statement.txt", BILL_TEXT)
    @folder.scan
    document = Document.last
    refute document.private?

    settled_file("private/statement copy.txt", BILL_TEXT)
    assert_no_difference -> { Document.count } do
      assert_enqueued_with(job: ProcessDocumentJob) { @folder.scan }
    end

    document.reload
    assert document.private?
    assert_equal "Added from the private folder", document.private_reason
    refute @root.join("private/statement copy.txt").exist?
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

  test "symlinks are skipped, logged by an opaque id and kept, even when they point inside the folder" do
    settled_file("elsewhere/statement.txt", BILL_TEXT)
    @root.join("linked.txt").make_symlink(@root.join("elsewhere/statement.txt"))
    logged = StringIO.new
    Rails.stubs(:logger).returns(ActiveSupport::Logger.new(logged))

    @folder.scan

    assert_equal 1, Document.where(source: "folder").count
    assert_equal "elsewhere/statement.txt", Document.last.source_detail
    assert @root.join("linked.txt").symlink?
    assert_match "[ingest] #{Ingest::Folder.log_id("linked.txt")}: skipped, symlinks are not imported", logged.string
    refute_match "linked", logged.string
  end

  test "log ids are short, stable and do not contain the filename" do
    id = Ingest::Folder.log_id("private/biopsy.pdf")

    assert_match(/\A\h{12}\z/, id)
    assert_equal id, Ingest::Folder.log_id("private/biopsy.pdf")
    refute_equal id, Ingest::Folder.log_id("private/biopsy2.pdf")
  end

  test "failures are logged without the filename" do
    settled_file("private/biopsy-jane.txt", BILL_TEXT)
    Document.stubs(:ingest!).raises(RuntimeError, "biopsy-jane")
    logged = capture_log

    @folder.scan

    assert_match "[ingest] #{Ingest::Folder.log_id("private/biopsy-jane.txt")}: RuntimeError", logged.string
    refute_match "biopsy", logged.string
    assert @root.join("private/biopsy-jane.txt").exist?
  end

  test "a folder swapped for a symlink after the check is not read or deleted" do
    Dir.mktmpdir do |outside|
      secret = Pathname(outside).join("statement.txt")
      secret.write(BILL_TEXT)
      @root.join("share").make_symlink(outside)
      @folder.stubs(:symlinked?).returns(false)
      logged = capture_log

      assert_no_difference -> { Document.count } do
        @folder.send(:ingest, @root.join("share/statement.txt"))
      end

      assert secret.exist?
      assert_match "#{Ingest::Folder.log_id("share/statement.txt")}: skipped, its folder changed", logged.string
    end
  end

  test "a folder swapped for a symlink while the file is read is not deleted through" do
    Dir.mktmpdir do |outside|
      secret = Pathname(outside).join("statement.txt")
      secret.write("someone else's file")
      settled_file("share/statement.txt", BILL_TEXT)
      swap = -> {
        @root.join("share").rename(@root.join("moved"))
        @root.join("share").make_symlink(outside)
      }
      Document.stubs(:ingest!).with { |**| swap.call || true }.returns(nil)

      @folder.scan

      assert secret.exist?
      assert @root.join("moved/statement.txt").exist?
    end
  end

  test "a duplicate is not deleted through a folder swapped for a symlink" do
    Dir.mktmpdir do |outside|
      secret = Pathname(outside).join("statement.txt")
      secret.write("someone else's file")
      settled_file("share/statement.txt", BILL_TEXT)
      Document.stubs(:ingest!).with { |**|
        @root.join("share").rename(@root.join("moved"))
        @root.join("share").make_symlink(outside)
      }.raises(Document::Duplicate.new(Document.new(original_filename: "statement.txt")))

      @folder.scan

      assert secret.exist?
      assert @root.join("moved/statement.txt").exist?
    end
  end

  test "rejected files stay in place when .unsupported is a symlink out of the folder" do
    Dir.mktmpdir do |outside|
      @root.join(".unsupported").make_symlink(outside)
      settled_file("letters/archive.exe", "MZ binary")
      logged = capture_log

      2.times { @folder.scan }

      assert @root.join("letters/archive.exe").exist?
      assert_empty Dir.children(outside)
      id = Ingest::Folder.log_id("letters/archive.exe")
      assert_equal 1, logged.string.scan("#{id}: UnsupportedType, left in place").size
      refute_match "archive", logged.string
    end
  end

  test "rejected files are not moved through a symlinked folder inside .unsupported" do
    Dir.mktmpdir do |outside|
      @root.join(".unsupported").mkpath
      @root.join(".unsupported/letters").make_symlink(outside)
      settled_file("letters/archive.exe", "MZ binary")

      @folder.scan

      assert @root.join("letters/archive.exe").exist?
      assert_empty Dir.children(outside)
    end
  end

  test "a symlink to a file outside the folder is not read or deleted" do
    Dir.mktmpdir do |outside|
      secret = Pathname(outside).join("passwd.txt")
      secret.write("root:x:0:0 secret contents")
      File.utime(1.minute.ago.to_time, 1.minute.ago.to_time, secret)
      @root.join("passwd.txt").make_symlink(secret)
      logged = StringIO.new
      Rails.stubs(:logger).returns(ActiveSupport::Logger.new(logged))

      assert_no_difference -> { Document.count } do
        @folder.scan
      end

      assert secret.exist?
      assert @root.join("passwd.txt").symlink?
      refute_match outside, logged.string
      refute_match "secret contents", logged.string
    end
  end

  test "files under a symlinked folder are skipped" do
    Dir.mktmpdir do |outside|
      secret = Pathname(outside).join("statement.txt")
      secret.write(BILL_TEXT)
      File.utime(1.minute.ago.to_time, 1.minute.ago.to_time, secret)
      @root.join("share").make_symlink(outside)

      assert_no_difference -> { Document.count } do
        @folder.scan
      end

      assert secret.exist?
    end
  end

  test "a file swapped for a symlink after the check is not followed" do
    Dir.mktmpdir do |outside|
      secret = Pathname(outside).join("passwd.txt")
      secret.write("secret contents")
      link = @root.join("swapped.txt")
      link.make_symlink(secret)
      @folder.stubs(:symlinked?).returns(false)

      assert_no_difference -> { Document.count } do
        @folder.send(:ingest, link)
      end

      assert secret.exist?
      assert link.symlink?
    end
  end

  test "a file already gone, as a deleted one an SMB share still lists, is skipped quietly" do
    Rails.logger.expects(:error).never

    assert_no_difference -> { Document.count } do
      @folder.send(:ingest, @root.join("private/gone.pdf"))
    end
    refute @root.join("private/gone.pdf").exist?
  end

  test "files over the upload limit move aside without being read" do
    settled_file("huge.txt", "x" * 2.kilobytes)
    Rails.configuration.x.stubs(:max_upload_bytes).returns(1.kilobyte)

    assert_no_difference -> { Document.count } do
      @folder.scan
    end
    assert @root.join(".unsupported/huge.txt").exist?
  end

  private
    def capture_log
      StringIO.new.tap { |logged| Rails.stubs(:logger).returns(ActiveSupport::Logger.new(logged)) }
    end

    def settled_file(relative, content)
      path = @root.join(relative)
      FileUtils.mkdir_p(path.dirname)
      path.write(content)
      File.utime(1.minute.ago.to_time, 1.minute.ago.to_time, path)
    end
end
