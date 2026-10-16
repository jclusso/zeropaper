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
    backup = Backup.create!(user: users(:one))
    backup.process!
    assert_equal "ready", backup.status, backup.error
    assert_equal 2, backup.documents_count

    Document.destroy_all
    restore = Restore.create!(user: users(:one), filename: backup.filename)
    restore.process!

    assert_equal "ready", restore.status, restore.error
    assert_equal 2, restore.restored_count

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
    path = Backup.file(backup.filename)
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

  test "only backups in the folder can be restored" do
    restore = Restore.new(user: users(:one), filename: "zeropaper-2026-01-01-030000.zpbackup")

    refute restore.save
    assert_includes restore.errors[:filename], "is not a backup in the backup folder"
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
    second = restore!(name)

    assert_operator second.restored_count, :>=, 1
    assert_equal "ready", stalled.reload.status
    assert stalled.chunks.any?
  end

  private
    def back_up_and_clear
      backup = Backup.create!(user: users(:one))
      backup.process!
      Document.destroy_all
      backup.filename
    end

    def restore!(name)
      restore = Restore.create!(user: users(:one), filename: name)
      restore.process!
      assert_equal "ready", restore.status, restore.error
      restore
    end
end
