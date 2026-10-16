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

  test "symlinks are skipped, logged by relative path and kept, even when they point inside the folder" do
    settled_file("elsewhere/statement.txt", BILL_TEXT)
    @root.join("linked.txt").make_symlink(@root.join("elsewhere/statement.txt"))
    logged = StringIO.new
    Rails.stubs(:logger).returns(ActiveSupport::Logger.new(logged))

    @folder.scan

    assert_equal 1, Document.where(source: "folder").count
    assert_equal "elsewhere/statement.txt", Document.last.source_detail
    assert @root.join("linked.txt").symlink?
    assert_match "[ingest] linked.txt: skipped, symlinks are not imported", logged.string
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

  test "files over the upload limit move aside without being read" do
    settled_file("huge.txt", "x" * 2.kilobytes)
    Rails.configuration.x.stubs(:max_upload_bytes).returns(1.kilobyte)

    assert_no_difference -> { Document.count } do
      @folder.scan
    end
    assert @root.join(".unsupported/huge.txt").exist?
  end

  private
    def settled_file(relative, content)
      path = @root.join(relative)
      FileUtils.mkdir_p(path.dirname)
      path.write(content)
      File.utime(1.minute.ago.to_time, 1.minute.ago.to_time, path)
    end
end
