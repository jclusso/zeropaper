require "test_helper"

class BackupTest < ActiveSupport::TestCase
  include BackupFolder

  setup do
    process(ingest(BILL_TEXT, filename: "statement.txt"))
    process(ingest("Diagnosis letter", filename: "diagnosis.txt", private: true, private_reason: "Uploaded as private"))
  end

  test "a backup is encrypted into the folder and nothing else is left there" do
    backup = Backup.create!
    backup.process!

    assert_equal "ready", backup.status, backup.error
    assert_equal 2, backup.documents_count
    assert_equal [ backup.filename ], Dir.children(@backup_dir)
    path = Backup.files.first
    assert Backup::Envelope.backup?(path)
    refute_includes path.binread, "Amount due"

    summary = Backup.summary(path)
    assert summary.own_key
    assert_equal 2, summary.documents_count
    assert_equal 1, summary.private_documents_count
    assert_equal "Schedule", summary.made_by
    assert_equal backup.created_at.to_i, summary.made_at.to_i
  end

  test "the key is made once and kept" do
    setting = Setting.instance
    key = setting.backup_key_bytes

    assert_equal 32, key.bytesize
    assert_equal key, Setting.instance.reload.backup_key_bytes
    refute_includes Setting.connection.select_value("SELECT backup_key FROM settings"), Backup::Key.encode(key)
  end

  test "pruning keeps the newest backup of each of the last days, weeks, months and years" do
    Setting.instance.update!(backup_keep_daily: 7, backup_keep_weekly: 4, backup_keep_monthly: 12, backup_keep_yearly: 2)
    today = Time.zone.parse("2026-10-16 03:00:00")
    (0...60).each { |days| put_backup("x", Backup.file_name(today - days.days)) }
    %w[2025-06-01 2024-03-01 2023-01-01].each { |day| put_backup("x", Backup.file_name(Time.zone.parse("#{day} 03:00:00"))) }
    put_backup("mine", "notes.zpbackup")

    Backup.prune

    kept = Backup.files.map { |path| path.basename.to_s[/\d{4}-\d{2}-\d{2}/] }
    assert_equal %w[
      2026-10-16 2026-10-15 2026-10-14 2026-10-13 2026-10-12 2026-10-11 2026-10-10
      2026-10-04 2026-09-30 2026-09-27 2026-08-31 2025-06-01 2024-03-01 2023-01-01
    ], kept
    assert File.exist?(File.join(@backup_dir, "notes.zpbackup"))
  end

  test "the newest backup is kept even when nothing else is" do
    Setting.instance.update!(backup_keep_daily: 0, backup_keep_weekly: 0, backup_keep_monthly: 0, backup_keep_yearly: 0)
    %w[zeropaper-2026-01-01-030000 zeropaper-2026-01-02-030000].each { |name| put_backup("x", "#{name}.zpbackup") }

    Backup.prune

    assert_equal [ "zeropaper-2026-01-02-030000.zpbackup" ], Backup.files.map { |path| path.basename.to_s }
  end

  test "a deleted backup an SMB share still lists is left out" do
    %w[zeropaper-2026-01-01-030000 zeropaper-2026-01-02-030000].each { |name| put_backup("x", "#{name}.zpbackup") }
    deleted = File.join(@backup_dir, "zeropaper-2026-01-02-030000.zpbackup")
    Backup.stubs(:openable?).with { |path| path.to_s == deleted }.returns(false)
    Backup.stubs(:openable?).with { |path| path.to_s != deleted }.returns(true)

    assert_equal [ "zeropaper-2026-01-01-030000.zpbackup" ], Backup.files.map { |path| path.basename.to_s }
    Backup.unstub(:openable?)
    refute Backup.send(:openable?, Pathname(@backup_dir).join("gone.zpbackup"))
    assert Backup.send(:openable?, Pathname(@backup_dir).join("zeropaper-2026-01-01-030000.zpbackup"))
  end

  test "symlinks in the folder are not listed or pruned" do
    target = File.join(@backup_dir, "secret.txt")
    File.write(target, "keep me")
    File.symlink(target, File.join(@backup_dir, "zeropaper-2026-01-01-030000.zpbackup"))
    Setting.instance.update!(backup_keep_daily: 1, backup_keep_weekly: 0, backup_keep_monthly: 0, backup_keep_yearly: 0)
    put_backup("x", "zeropaper-2026-01-02-030000.zpbackup")

    Backup.prune

    assert_equal [ "zeropaper-2026-01-02-030000.zpbackup" ], Backup.files.map { |path| path.basename.to_s }
    assert File.symlink?(File.join(@backup_dir, "zeropaper-2026-01-01-030000.zpbackup"))
    assert_equal "keep me", File.read(target)
  end

  test "a symlink planted at the partial file name is not written through" do
    target = File.join(@backup_dir, "secret.txt")
    File.write(target, "keep me")
    backup = Backup.create!
    File.symlink(target, File.join(@backup_dir, ".#{Backup.file_name(backup.created_at)}.partial"))

    backup.process!

    assert_equal "failed", backup.status
    assert_equal "keep me", File.read(target)
  end

  test "an older export is checked, encrypted and named for when it was made" do
    made_at = Time.zone.parse("2025-03-01 09:30:00")
    zip = build_zip(manifest: { format: Archive::FORMAT, version: 1, exported_at: made_at.iso8601 })

    path = upload_file(zip) { |upload| Backup.import(upload) }

    assert_equal Backup.file_name(made_at), path.basename.to_s
    assert Backup::Envelope.backup?(path)
    Backup.open_zip(path, Setting.instance.backup_key_bytes) { |plain| assert_equal zip, File.binread(plain) }
  end

  test "an upload already in the folder is refused" do
    backup = Backup.create!
    backup.process!
    copy = File.binread(File.join(@backup_dir, backup.filename))

    error = assert_raises(Archive::Reader::InvalidArchive) { upload_file(copy) { |upload| Backup.import(upload) } }

    assert_match "is already in the folder", error.message
    assert_equal 1, Backup.files.size
  end

  test "a backup made with another key is kept as it is and marked" do
    other = Backup::Key.parse(Backup::Key.generate)
    name = put_sealed(build_zip, key: other)
    sealed = File.binread(File.join(@backup_dir, name))
    File.delete(File.join(@backup_dir, name))

    path = upload_file(sealed) { |upload| Backup.import(upload) }

    assert_equal sealed, path.binread
    summary = Backup.summary(path)
    refute summary.own_key
    assert_equal Backup::Key.id(other), summary.key_id
  end

  test "uploads that are not sound backups are refused and leave nothing behind" do
    damaged = build_zip({ "documents/1/file/statement.txt" => "Amount due 42.00" })
    damaged[damaged.index("42.00"), 5] = "99.99"

    assert_raises(Archive::Reader::InvalidArchive, "That file is not a ZeroPaper backup.") { upload_file("hello") { |upload| Backup.import(upload) } }
    assert_raises(Archive::Reader::InvalidArchive) { upload_file(build_zip(manifest: { format: "other" })) { |upload| Backup.import(upload) } }
    error = assert_raises(Archive::Reader::InvalidArchive) { upload_file(damaged) { |upload| Backup.import(upload) } }
    assert_equal "documents/1/file/statement.txt is damaged.", error.message
    assert_empty Dir.children(@backup_dir)
  end

  test "a backup that cannot decrypt a document says why" do
    Document.any_instance.stubs(:content).raises(ActiveRecord::Encryption::Errors::Decryption)
    backup = Backup.create!
    backup.process!

    assert_equal "failed", backup.status
    assert_match "different encryption keys", backup.error
  end

  test "a backup names the document whose file is missing from storage" do
    document = Document.find_by!(original_filename: "statement.txt")
    document.file.blob.service.delete(document.file.blob.key)
    backup = Backup.create!
    backup.process!

    assert_equal "failed", backup.status
    assert_match "(document #{document.id}) is missing its file in storage", backup.error
  end

  test "the schedule backs up when the last backup is older than the interval and prunes" do
    Setting.instance.update!(backup_enabled: true, backup_frequency: "daily", backup_keep_daily: 1, backup_keep_weekly: 0, backup_keep_monthly: 0, backup_keep_yearly: 0)
    put_backup("x", "zeropaper-2026-01-01-030000.zpbackup")

    first = Backup.run_scheduled
    assert_equal "ready", first.status, first.error
    assert_equal [ first.filename ], Backup.files.map { |path| path.basename.to_s }
    assert_nil Backup.run_scheduled

    first.update!(created_at: 23.hours.ago - 31.minutes)
    assert_difference -> { Backup.count } do
      Backup.run_scheduled
    end
  end

  test "a failed backup is retried and listed until one works" do
    Setting.instance.update!(backup_enabled: true)
    failed = Backup.create!(status: "failed", error: "NAS offline")
    assert_equal [ failed ], Backup.unfinished.to_a

    Backup.run_scheduled

    assert_empty Backup.unfinished
  end

  test "nothing runs while the schedule is off" do
    assert_nil Backup.run_scheduled
    assert_equal 0, Backup.count
  end
end
