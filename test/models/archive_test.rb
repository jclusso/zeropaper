require "test_helper"

class ArchiveTest < ActiveSupport::TestCase
  setup do
    @document = ingest(BILL_TEXT, filename: "statement.txt")
    process(@document)
    @document.update!(title: "March statement", tag_names: [ "Utilities" ])
    @private = ingest("Diagnosis letter", filename: "diagnosis.txt", private: true, private_reason: "Uploaded as private")
    process(@private)
  end

  test "export then restore brings documents back without sending anything out" do
    export = Export.create!(user: users(:one), include_private: true)
    export.process!
    assert_equal "ready", export.status
    assert_equal 2, export.documents_count
    assert_equal "test_private", export.archive.blob.service_name

    data = export.archive.download
    Document.destroy_all

    restore = Restore.new(user: users(:one))
    restore.archive.attach(io: StringIO.new(data), filename: "export.zip", content_type: "application/zip")
    restore.save!
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
    assert_equal "test_private", restored_private.file.blob.service_name
    assert_no_hosted_ai_requests
  end

  test "export can leave private documents out" do
    export = Export.create!(user: users(:one), include_private: false)
    export.process!

    assert_equal 1, export.documents_count
  end

  test "restoring skips documents already in the library" do
    export = Export.create!(user: users(:one))
    export.process!

    restore = Restore.new(user: users(:one))
    restore.archive.attach(io: StringIO.new(export.archive.download), filename: "export.zip", content_type: "application/zip")
    restore.save!
    restore.process!

    assert_equal 0, restore.restored_count
    assert_equal 2, restore.skipped_count
  end

  test "a zip that is not an export fails cleanly" do
    restore = Restore.new(user: users(:one))
    zip = Zip::OutputStream.write_buffer { |stream| stream.put_next_entry("hello.txt"); stream.write("hi") }.string
    restore.archive.attach(io: StringIO.new(zip), filename: "other.zip", content_type: "application/zip")
    restore.save!
    restore.process!

    assert_equal "failed", restore.status
    assert_match "manifest.json is missing", restore.error
  end

  test "an older export's private correspondent comes back as a rule" do
    manifest = { format: Archive::FORMAT, version: 1, correspondents: [ { name: "Harbor Hospital", auto_match: true, private_documents: true } ] }
    zip = Zip::OutputStream.write_buffer { |stream| stream.put_next_entry("manifest.json"); stream.write(manifest.to_json) }.string
    restore = Restore.new(user: users(:one))
    restore.archive.attach(io: StringIO.new(zip), filename: "old.zip", content_type: "application/zip")
    restore.save!
    restore.process!

    assert_equal "ready", restore.status
    rule = Rule.find_by!(name: "Private: Harbor Hospital")
    assert rule.mark_private?
    assert_equal Correspondent.named("Harbor Hospital"), rule.correspondent
  end
end
