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
    assert_no_external_requests
  end

  test "export can leave private documents out" do
    export = Export.create!(user: users(:one), include_private: false)
    export.process!

    assert_equal 1, export.documents_count
  end

  test "restore runs this library's mark-private rules before a document can be shared" do
    export = Export.create!(user: users(:one), include_private: false)
    export.process!
    data = export.archive.download
    Document.destroy_all
    Rule.create!(name: "Power bills", conditions: [ { field: "content", operator: "phrase", value: "Amount due" } ], mark_private: true)

    restore!(data)

    restored = Document.find_by!(original_filename: "statement.txt")
    assert restored.private?
    assert_equal "Matched rule “Power bills”", restored.private_reason
    assert_equal "test_private", restored.file.blob.service_name
    assert_equal "test_private", restored.thumbnail.blob.service_name if restored.thumbnail.attached?
    assert_no_external_requests
  end

  test "restore runs filename and source rules too" do
    export = Export.create!(user: users(:one), include_private: false)
    export.process!
    data = export.archive.download
    Document.destroy_all
    Rule.create!(name: "Restored files", conditions: [ { field: "source", operator: "is", value: "restore" } ], mark_private: true)

    restore!(data)

    assert Document.find_by!(original_filename: "statement.txt").private?
  end

  test "an export without private documents leaves out what could describe them" do
    surgeon = Correspondent.create!(name: "Secret Surgeon")
    biopsy = DocumentType.create!(name: "Biopsy Report")
    @private.update!(correspondent: surgeon, document_type: biopsy, tag_names: [ "Oncology" ])
    Rule.create!(name: "File surgeon letters", conditions: [ { field: "content", operator: "phrase", value: "pathology" } ], correspondent: surgeon)
    Rule.create!(name: "Tag bills", conditions: [ { field: "content", operator: "phrase", value: "Amount due" } ], tag_ids: [ Tag.named("Utilities").id ])

    shareable = manifest(include_private: false)
    names = %w[correspondents document_types tags].to_h { |key| [ key, shareable[key].map { |record| record["name"] } ] }
    refute_includes names["correspondents"], "Secret Surgeon"
    refute_includes names["document_types"], "Biopsy Report"
    refute_includes names["tags"], "Oncology"
    assert_includes names["correspondents"], "Acme Power"
    assert_includes names["tags"], "Utilities"
    rules = shareable["rules"].map { |rule| rule["name"] }
    assert_includes rules, "Tag bills"
    refute_includes rules, "File surgeon letters", "a rule naming a private-only correspondent is left out"
    assert shareable["rules"].none? { |rule| rule["mark_private"] }, "mark-private rules are left out"
    refute_includes rules, "Private: City Clinic"

    everything = manifest(include_private: true)
    assert_includes everything["correspondents"].map { |record| record["name"] }, "Secret Surgeon"
    assert_includes everything["rules"].map { |rule| rule["name"] }, "Private: City Clinic"
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

  private
    def restore!(data)
      restore = Restore.new(user: users(:one))
      restore.archive.attach(io: StringIO.new(data), filename: "export.zip", content_type: "application/zip")
      restore.save!
      restore.process!
      assert_equal "ready", restore.status, restore.error
      restore
    end

    def manifest(include_private:)
      export = Export.create!(user: users(:one), include_private: include_private)
      export.process!
      JSON.parse(Zip::File.open_buffer(StringIO.new(export.archive.download)).read("manifest.json"))
    end
end
