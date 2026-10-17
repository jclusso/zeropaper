require "test_helper"

class ArchiveTest < ActiveSupport::TestCase
  include BackupFolder

  setup do
    @document = ingest(BILL_TEXT, filename: "statement.txt")
    process(@document)
    @document.update!(title: "March statement", tag_names: [ "Utilities" ])
    @private = ingest("Diagnosis letter", filename: "diagnosis.txt", private: true, private_reason: "Uploaded as private")
    process(@private)
  end

  test "a backup then restore brings documents back without sending anything out" do
    blank = ingest("No words here", filename: "photo.txt")
    blank.update!(content: nil, status: "ready")
    backup = Backup.create!(user: users(:one))
    backup.process!
    assert_equal "ready", backup.status, backup.error
    assert_equal 3, backup.documents_count

    Document.destroy_all
    restore = Restore.create!(user: users(:one), filename: backup.filename)
    restore.process!

    assert_equal "ready", restore.status, restore.error
    assert_equal 3, restore.restored_count
    assert_equal "", Document.find_by!(original_filename: "photo.txt").content.to_s

    restored = Document.find_by!(original_filename: "statement.txt")
    assert_equal "March statement", restored.title
    assert_equal [ "Utilities" ], restored.tags.map(&:name)
    assert_equal correspondents(:acme_power), restored.correspondent
    assert_match "Amount due", restored.content
    assert restored.chunks.any?
    assert_equal BILL_TEXT, restored.file.download

    restored_private = Document.find_by!(original_filename: "diagnosis.txt")
    assert restored_private.private?
    assert_no_external_requests
  end

  test "restore runs this library's mark-private rules before a document can be shared" do
    name = back_up_and_clear
    Rule.create!(name: "Power bills", conditions: [ { field: "content", operator: "phrase", value: "Amount due" } ], mark_private: true)

    restore!(name)

    restored = Document.find_by!(original_filename: "statement.txt")
    assert restored.private?
    assert_equal "Matched rule “Power bills”", restored.private_reason
    assert_no_external_requests
  end

  test "restore runs filename and source rules too" do
    name = back_up_and_clear
    Rule.create!(name: "Restored files", conditions: [ { field: "source", operator: "is", value: "restore" } ], mark_private: true)

    restore!(name)

    assert Document.find_by!(original_filename: "statement.txt").private?
  end

  test "restoring skips documents already in the library" do
    backup = Backup.create!(user: users(:one))
    backup.process!

    restore = Restore.create!(user: users(:one), filename: backup.filename)
    restore.process!

    assert_equal 0, restore.restored_count
    assert_equal 2, restore.skipped_count
  end

  test "two documents with the same file both come back, and both are skipped once here" do
    copy = ingest("Another statement", filename: "copy.txt")
    process(copy)
    copy.file.attach(io: StringIO.new(BILL_TEXT), filename: "copy.txt", content_type: "text/plain")
    copy.update!(checksum: @document.checksum, title: "Statement copy")
    name = back_up_and_clear

    restore = restore!(name)

    assert_equal 3, restore.restored_count
    assert_equal [ "March statement", "Statement copy" ], Document.where(checksum: @document.checksum).order(:id).map(&:title)

    restore = restore!(name)
    assert_equal 0, restore.restored_count
    assert_equal 3, restore.skipped_count
  end

  test "a zip that is not a backup fails cleanly" do
    name = put_sealed(Zip::OutputStream.write_buffer { |stream| stream.put_next_entry("hello.txt"); stream.write("hi") }.string)
    restore = Restore.create!(user: users(:one), filename: name)
    restore.process!

    assert_equal "failed", restore.status
    assert_match "manifest.json is missing", restore.error
  end

  test "a backup with a document that does not match its checksum restores nothing" do
    backup = Backup.create!(user: users(:one))
    backup.process!
    Document.destroy_all
    Tag.destroy_all

    # Seal the zip again with one file changed, so every CRC and tag is right.
    path = backup.path
    entries = Backup.open_zip(path, Setting.instance.backup_key_bytes) do |zip|
      Zip::File.open(zip) { |archive| archive.entries.select(&:file?).to_h { |entry| [ entry.name, entry.get_input_stream.read ] } }
    end
    entries[entries.keys.find { |name| name.include?("/file/statement.txt") }] = "Amount due: nothing"
    path.delete
    name = put_sealed(Zip::OutputStream.write_buffer { |zip| entries.each { |entry, data| zip.put_next_entry(entry); zip.write(data) } }.string)

    restore = Restore.create!(user: users(:one), filename: name)
    restore.process!

    assert_equal "failed", restore.status
    assert_equal "March statement does not match the checksum it was backed up with.", restore.error
    assert_equal 0, Document.count
    assert_equal 0, Tag.count
  end

  test "a truncated backup restores nothing" do
    backup = Backup.create!(user: users(:one))
    backup.process!
    Document.destroy_all
    path = File.join(@backup_dir, backup.filename)
    File.truncate(path, File.size(path) / 2)

    restore = Restore.create!(user: users(:one), filename: backup.filename)
    restore.process!

    assert_equal "failed", restore.status
    assert_match(/cut short|damaged/, restore.error)
    assert_equal 0, Document.count
  end

  test "a backup made with another key restores with that key, which is then forgotten" do
    other = Backup::Key.generate
    name = put_sealed(build_zip, key: Backup::Key.parse(other))

    refute Restore.new(user: users(:one), filename: name).save
    wrong = Restore.new(user: users(:one), filename: name, key: Backup::Key.generate)
    refute wrong.save
    assert_includes wrong.errors[:key], "is not the key this backup was made with"

    restore = Restore.create!(user: users(:one), filename: name, key: "Key file:\n#{other}\n")
    restore.process!

    assert_equal "ready", restore.status, restore.error
    assert_nil restore.reload.key
  end

  test "only listed backups can be restored" do
    restore = Restore.new(user: users(:one), filename: "zeropaper-2026-01-01-030000.zpbackup")

    refute restore.save
    assert_includes restore.errors[:filename], "is not a listed backup"
  end

  test "an older export's private correspondent comes back as a rule" do
    manifest = { format: Archive::FORMAT, version: 1, correspondents: [ { name: "Harbor Hospital", auto_match: true, private_documents: true } ] }
    name = put_sealed(build_zip(manifest: manifest))
    restore = Restore.create!(user: users(:one), filename: name)
    restore.process!

    assert_equal "ready", restore.status
    rule = Rule.find_by!(name: "Private: Harbor Hospital")
    assert rule.mark_private?
    assert_equal Correspondent.named("Harbor Hospital"), rule.correspondent
  end

  test "a restore that failed while indexing resumes the document when run again" do
    name = back_up_and_clear

    Embedder.stubs(:embed_documents).raises(RuntimeError, "model missing")
    first = Restore.create!(user: users(:one), filename: name)
    first.process!
    assert_equal "failed", first.status
    stalled = Document.find_by!(original_filename: "statement.txt")
    refute_equal "ready", stalled.status
    assert_empty stalled.chunks

    Embedder.unstub(:embed_documents)
    Rule.create!(name: "Power bills", conditions: [ { field: "content", operator: "phrase", value: "Amount due" } ], mark_private: true)
    second = restore!(name)

    assert_operator second.restored_count, :>=, 1
    assert_equal "ready", stalled.reload.status
    assert stalled.chunks.any?
    assert stalled.private?, "this library's rules run again before a resumed document is ready"
    assert_equal "Matched rule “Power bills”", stalled.private_reason
  end

  test "a private copy in the backup makes the shareable document already here private" do
    name = Backup.create!(user: users(:one)).tap(&:process!).filename
    @private.update!(private: false, private_reason: nil)
    refute @private.reload.private?

    restore = restore!(name)

    assert_equal 2, restore.skipped_count
    assert @private.reload.private?
    assert_equal "Uploaded as private", @private.private_reason
  end

  test "a restore runs once, however often its job does" do
    name = back_up_and_clear
    restore = restore!(name)

    Archive::Reader.expects(:new).never
    restore.process!

    assert_equal "ready", restore.reload.status
    assert_equal 2, restore.restored_count
  end

  test "a document missing its details or holding a file ZeroPaper does not keep restores nothing" do
    svg = %(<svg xmlns="http://www.w3.org/2000/svg"><text y="20">hi</text></svg>)
    html = "<h1>Sign in again</h1><form action='/session' method='post'>"
    {
      { "documents/1/content.txt" => "x", "documents/1/file/a.txt" => "x" } => "documents/1/document.json is missing",
      { "documents/1/document.json" => "[1]", "documents/1/file/a.txt" => "x" } => "documents/1/document.json is damaged.",
      document_entries("evil.svg", svg) => "evil.svg holds a image/svg+xml file, which ZeroPaper does not keep.",
      document_entries("page.html", html) => "page.html holds a text/html file, which ZeroPaper does not keep.",
      document_entries("a.txt", "x").merge("documents/1/thumbnail.jpg" => svg) => "a.txt holds a image/svg+xml file, which ZeroPaper does not keep."
    }.each do |entries, message|
      Document.destroy_all
      error = assert_raises(Archive::Reader::InvalidArchive) { upload_file(build_zip(entries)) { |upload| Backup.import(upload) } }
      assert_equal message, error.message

      name = put_sealed(build_zip(entries), made_at: 1.day.ago)
      restore = Restore.create!(user: users(:one), filename: name)
      restore.process!
      assert_equal "failed", restore.status
      assert_equal message, restore.error
      assert_equal 0, Document.count
      File.delete(File.join(@backup_dir, name))
    end
  end

  test "a restored file's type comes from its bytes, not from the backup's details" do
    Document.destroy_all
    name = put_sealed(build_zip(document_entries("notes.txt", "Plain words", content_type: "text/html")))

    restore!(name)

    document = Document.find_by!(original_filename: "notes.txt")
    assert_equal "text/plain", document.content_type
    assert_equal "text/plain", document.file.blob.content_type
  end

  test "a restore whose backup unzips past the limits fails before reading anything" do
    Rails.configuration.x.stubs(:max_upload_bytes).returns(1.megabyte)
    other = Backup::Key.generate
    name = put_sealed(Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("manifest.json")
      zip.write({ format: Archive::FORMAT, version: Archive::VERSION }.to_json)
      zip.put_next_entry("documents/1/file/bomb.txt")
      zip.write("0" * 5.megabytes)
    end.string, key: Backup::Key.parse(other))
    Zlib.expects(:crc32).never

    restore = Restore.create!(user: users(:one), filename: name, key: other)
    perform_enqueued_jobs { restore.process_later }

    assert_equal "failed", restore.reload.status
    assert_equal "documents/1/file/bomb.txt unzips to more than the 4 MB limit.", restore.error
  end

  test "a backup made with this key restores files larger than a since lowered upload limit" do
    Document.destroy_all
    data = "0" * 5.megabytes
    entries = document_entries("big.txt", data).merge("documents/1/content.txt" => "Big file")
    name = put_sealed(build_zip(entries))
    Rails.configuration.x.stubs(:max_upload_bytes).returns(1.megabyte)

    restore!(name)

    assert_equal data.bytesize, Document.find_by!(original_filename: "big.txt").file.byte_size
  end

  test "a document's text has its own limit, whatever the key" do
    Document.destroy_all
    stub_const(Archive::Reader, :MAX_CONTENT_BYTES, 1.megabyte) do
      name = put_sealed(build_zip(document_entries("a.txt", "x").merge("documents/1/content.txt" => "x" * 2.megabytes)))

      restore = Restore.create!(user: users(:one), filename: name)
      restore.process!

      assert_equal "failed", restore.status
      assert_equal "documents/1/content.txt unzips to more than the 1 MB limit.", restore.error
      assert_equal 0, Document.count
    end
  end

  test "a damaged archive PDF in a later document fails the check and restores nothing" do
    Document.destroy_all
    pdf = "%PDF-1.4\n#{"intact " * 20_000}\n%%EOF\n"
    entries = {
      "documents/1/document.json" => { checksum: Digest::SHA256.hexdigest("first"), original_filename: "first.txt" }.to_json,
      "documents/1/file/first.txt" => "first",
      "documents/2/document.json" => { checksum: Digest::SHA256.hexdigest("second"), original_filename: "second.txt" }.to_json,
      "documents/2/file/second.txt" => "second",
      "documents/2/archive.pdf" => pdf
    }
    zip = build_zip(entries).b
    # Change bytes past what is read to tell the file's type, leaving the CRC as it was.
    offset = zip.index(pdf.b) + pdf.bytesize - 20
    zip[offset, 6] = "broken"
    name = put_sealed(zip)

    error = assert_raises(Archive::Reader::InvalidArchive) do
      Backup.open_zip(Pathname(@backup_dir).join(name), Setting.instance.backup_key_bytes) { |path| Archive::Reader.new(path).verify! }
    end
    assert_equal "documents/2/archive.pdf is damaged.", error.message

    restore = Restore.create!(user: users(:one), filename: name)
    restore.process!

    assert_equal "failed", restore.status
    assert_equal 0, Document.count
  end

  test "a backup sealed ahead of this clock restores" do
    Document.destroy_all
    name = put_sealed(build_zip(document_entries("ahead.txt", "From a fast clock")), made_at: 2.hours.from_now)

    restore!(name)

    assert Document.exists?(original_filename: "ahead.txt")
  end

  test "a restore whose backup decrypts past the whole backup limit stops" do
    name = back_up_and_clear
    Rails.configuration.x.stubs(:max_backup_bytes).returns(1.kilobyte)

    restore = Restore.create!(user: users(:one), filename: name)
    perform_enqueued_jobs { restore.process_later }

    assert_equal "failed", restore.reload.status
    assert_equal "This backup is larger than the 1 KB backup limit (MAX_BACKUP_GB).", restore.error
    assert_empty Dir.children(@scratch_dir)
  end

  private
    def back_up_and_clear
      backup = Backup.create!(user: users(:one))
      backup.process!
      Document.destroy_all
      backup.filename
    end

    # A document's entries as a backup holds them.
    def document_entries(filename, data, content_type: "application/pdf")
      {
        "documents/1/document.json" => { checksum: Digest::SHA256.hexdigest(data), original_filename: filename, content_type: content_type, title: filename }.to_json,
        "documents/1/content.txt" => data,
        "documents/1/file/#{filename}" => data
      }
    end

    # Restores find backups by their records, so files put in the folder here
    # are recorded.
    def put_sealed(...)
      super.tap { Backup.record_existing_files }
    end

    def restore!(name)
      restore = Restore.create!(user: users(:one), filename: name)
      restore.process!
      assert_equal "ready", restore.status, restore.error
      restore
    end
end
