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

    assert backup.own_key?
    refute backup.uploaded
    assert_equal path.size, backup.size
    assert_equal 1, backup.private_documents_count
    assert_equal "Schedule", backup.made_by
    assert_equal backup.created_at.to_i, backup.made_at.to_i
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
    travel_to Time.zone.parse("2026-10-16 12:00:00")
    today = Time.zone.parse("2026-10-16 03:00:00")
    zip = build_zip
    (0...60).each { |days| put_sealed(zip, made_at: today - days.days) }
    %w[2025-06-01 2024-03-01 2023-01-01].each { |day| put_sealed(zip, made_at: Time.zone.parse("#{day} 03:00:00")) }
    put_backup("mine", "notes.zpbackup")
    Backup.sync

    Backup.prune

    kept = Backup.files.map { |path| path.basename.to_s[/\d{4}-\d{2}-\d{2}/] }
    assert_equal %w[
      2026-10-16 2026-10-15 2026-10-14 2026-10-13 2026-10-12 2026-10-11 2026-10-10
      2026-10-04 2026-09-30 2026-09-27 2026-08-31 2025-06-01 2024-03-01 2023-01-01
    ], kept
    assert_equal Backup.files.map { |path| path.basename.to_s }, Backup.stored.order(made_at: :desc).pluck(:filename)
    assert File.exist?(File.join(@backup_dir, "notes.zpbackup"))
  end

  test "the newest backup is kept even when nothing else is" do
    Setting.instance.update!(backup_keep_daily: 0, backup_keep_weekly: 0, backup_keep_monthly: 0, backup_keep_yearly: 0)
    %w[2026-01-01 2026-01-02].each { |day| put_sealed(build_zip, made_at: Time.zone.parse("#{day} 03:00:00")) }
    Backup.sync

    Backup.prune

    assert_equal [ "zeropaper-2026-01-02-030000.zpbackup" ], Backup.files.map { |path| path.basename.to_s }
  end

  test "sync records files added by hand, forgets files deleted by hand and fills in missing details" do
    added = put_sealed(build_zip, made_at: Time.zone.parse("2026-01-01 03:00:00"))
    deleted = put_sealed(build_zip, made_at: Time.zone.parse("2026-01-02 03:00:00"))
    Backup.sync
    assert_equal [ added, deleted ].sort, Backup.stored.pluck(:filename).sort

    File.delete(File.join(@backup_dir, deleted))
    Backup.stored.find_by!(filename: added).update_columns(made_at: nil, size: nil)
    Backup.sync

    backup = Backup.stored.sole
    assert_equal added, backup.filename
    assert_equal Time.zone.parse("2026-01-01 03:00:00"), backup.made_at
    assert_equal File.size(File.join(@backup_dir, added)), backup.size
    refute backup.uploaded
    assert backup.own_key?
  end

  test "removing a backup deletes its file and its record" do
    backup = Backup.create!
    backup.process!

    backup.remove!

    assert_empty Dir.children(@backup_dir)
    refute Backup.exists?(backup.id)
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

  test "pruning leaves uploaded, foreign, unreadable and future dated backups alone, and they take no place" do
    Setting.instance.update!(backup_keep_daily: 1, backup_keep_weekly: 0, backup_keep_monthly: 0, backup_keep_yearly: 0)
    travel_to Time.zone.parse("2026-10-16 12:00:00")
    zip = build_zip
    long_ago = Time.zone.parse("2020-01-01 03:00:00")
    uploaded = put_sealed(zip, made_at: long_ago, name: Backup.file_name(long_ago, uploaded: true))
    foreign = put_sealed(zip, made_at: Time.zone.parse("2021-01-01 03:00:00"), key: Backup::Key.parse(Backup::Key.generate))
    unreadable = put_backup("x", "zeropaper-2022-01-01-030000.zpbackup")
    future = put_backup("x", "zeropaper-2099-01-01-030000.zpbackup")
    old = put_sealed(zip, made_at: Time.zone.parse("2026-10-14 03:00:00"))
    newest = put_sealed(zip, made_at: Time.zone.parse("2026-10-15 03:00:00"))
    Backup.sync

    Backup.prune

    assert_equal [ future, newest, unreadable, foreign, uploaded ], Backup.files.map { |path| path.basename.to_s }
    refute File.exist?(File.join(@backup_dir, old))
  end

  test "symlinks in the folder are not listed or pruned" do
    target = File.join(@backup_dir, "secret.txt")
    File.write(target, "keep me")
    File.symlink(target, File.join(@backup_dir, "zeropaper-2026-01-01-030000.zpbackup"))
    Setting.instance.update!(backup_keep_daily: 1, backup_keep_weekly: 0, backup_keep_monthly: 0, backup_keep_yearly: 0)
    put_sealed(build_zip, made_at: Time.zone.parse("2026-01-02 03:00:00"))
    Backup.sync

    Backup.prune

    assert_equal [ "zeropaper-2026-01-02-030000.zpbackup" ], Backup.files.map { |path| path.basename.to_s }
    assert_equal [ "zeropaper-2026-01-02-030000.zpbackup" ], Backup.stored.pluck(:filename)
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

    backup = upload_file(zip) { |upload| Backup.import(upload) }
    path = backup.path

    assert_equal "zeropaper-2025-03-01-093000-uploaded.zpbackup", backup.filename
    assert backup.uploaded
    assert_equal made_at, backup.made_at
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

    backup = upload_file(sealed) { |upload| Backup.import(upload) }

    assert_equal sealed, backup.path.binread
    refute backup.own_key?
    assert_equal Backup::Key.id(other), backup.key_id
  end

  test "uploads that are not sound backups are refused and leave nothing behind" do
    damaged = build_zip({ "documents/1/document.json" => { checksum: Digest::SHA256.hexdigest("Amount due 42.00") }.to_json, "documents/1/file/statement.txt" => "Amount due 42.00" })
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
    put_sealed(build_zip, made_at: Time.zone.parse("2026-01-01 03:00:00"))
    Backup.sync

    first = Backup.run_scheduled
    assert_equal "ready", first.status, first.error
    assert_equal [ first.filename ], Backup.files.map { |path| path.basename.to_s }
    assert_nil Backup.run_scheduled

    first.update!(made_at: 23.hours.ago - 31.minutes)
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

  test "a backup works in a scratch folder it removes, and folders left by a dead run are removed" do
    dead = File.join(@scratch_dir, "dead")
    FileUtils.mkdir_p(dead)
    File.write(File.join(dead, "backup.zip"), "Diagnosis letter")
    busy = File.join(@scratch_dir, "busy")
    FileUtils.mkdir_p(busy)
    [ dead, busy ].each { |dir| File.utime(2.minutes.ago.to_time, 2.minutes.ago.to_time, dir) }
    plain_zips = []
    Archive::Reader.any_instance.stubs(:verify!).with { plain_zips << Dir.glob(File.join(@scratch_dir, "*", "backup.zip")); true }

    File.open(File.join(busy, Backup::Scratch::LOCK), "w") do |lock|
      lock.flock(File::LOCK_EX)
      backup = Backup.create!
      backup.process!
      assert_equal "ready", backup.status, backup.error
    end

    assert_equal 1, plain_zips.flatten.size
    assert_equal [ "busy" ], Dir.children(@scratch_dir)
  end

  test "a backup runs once, however often its job does" do
    backup = Backup.create!
    backup.process!
    assert_equal "ready", backup.status, backup.error

    Archive::Writer.expects(:new).never
    backup.process!

    assert_equal "ready", backup.reload.status
    assert_equal [ backup.filename ], Dir.children(@backup_dir)
  end

  test "a backup another process is running is left to it" do
    backup = Backup.create!
    other = PG.connect(Backup.connection.raw_connection.conninfo_hash.compact_blank)
    assert other.exec_params("SELECT pg_try_advisory_lock(hashtextextended($1, 0))", [ "Backup/#{backup.id}" ]).getvalue(0, 0)

    backup.process!

    assert_equal "pending", backup.reload.status
    assert_empty Dir.children(@backup_dir)
  ensure
    other&.close
  end

  test "a backup swapped for a FIFO after it was listed is refused rather than hanging" do
    fifo = File.join(@backup_dir, "zeropaper-2026-01-01-030000.zpbackup")
    File.mkfifo(fifo)
    regular = File.lstat(File.join(@backup_dir, put_backup("x", "zeropaper-2026-01-02-030000.zpbackup")))
    File.stubs(:lstat).with(fifo).returns(regular)

    Timeout.timeout(5) do
      assert_raises(Backup::Envelope::Invalid) { Backup.open_file(fifo) }
      assert Backup.send(:openable?, Pathname(fifo))
    end
    File.unstub(:lstat)
    assert_equal [ "zeropaper-2026-01-02-030000.zpbackup" ], Backup.files.map { |path| path.basename.to_s }
  end

  test "a backup swapped for a link or another file after it was listed is not read" do
    name = put_sealed(build_zip)
    path = Pathname(@backup_dir).join(name)
    target = File.join(@backup_dir, "secret.txt")
    File.write(target, "keep me")
    regular = File.lstat(target)

    # Swapped for another file between the check and the open.
    File.stubs(:lstat).returns(regular)
    error = assert_raises(Backup::Envelope::Invalid) { Backup::Envelope.new(path.to_s).header }
    assert_equal "#{name} changed while it was opened.", error.message

    # Swapped for a link between the check and the open.
    File.delete(path)
    File.symlink(target, path)
    error = assert_raises(Backup::Envelope::Invalid) { Backup::Envelope.new(path.to_s).header }
    assert_equal "#{name} is a link, not a backup.", error.message
  ensure
    File.unstub(:lstat)
  end

  test "a backup file with a malformed header is listed as unreadable and refused as an upload" do
    nonce = Base64.strict_encode64("12345678")
    good = { version: 1, made_at: 1.day.ago.iso8601, key_id: "abcd1234", nonce: nonce }
    [
      "[1]", "null", "not json",
      good.merge(made_at: "2026-99-99T00:00:00Z"), good.merge(made_at: 5),
      good.merge(nonce: "AAAA"), good.merge(nonce: "not base64!"), good.except(:key_id), good.merge(version: "1"), good.merge(version: 2)
    ].each do |header|
      header = header.to_json unless header.is_a?(String)
      bytes = Backup::Envelope::MAGIC + [ header.bytesize ].pack("N") + header
      path = Pathname(File.join(@backup_dir, put_backup(bytes, "zeropaper-2026-01-01-030000.zpbackup")))

      Backup.sync
      refute Backup.stored.sole.readable?, header
      assert_raises(Archive::Reader::InvalidArchive, header) { upload_file(bytes) { |upload| Backup.import(upload) } }
      Backup.stored.sole.remove!
    end
    assert_empty Dir.children(@backup_dir)
  end

  test "a backup that fails to read for any other reason is listed as unreadable" do
    path = Pathname(@backup_dir).join(put_sealed(build_zip))
    Backup::Envelope.any_instance.stubs(:metadata).raises(TypeError, "no implicit conversion")

    Backup.sync

    backup = Backup.stored.sole
    refute backup.readable?
    assert_equal path.size, backup.size
    assert_equal path.mtime.to_i, backup.made_at.to_i
  end

  test "an upload dated in the future is named for now" do
    travel_to Time.zone.parse("2026-10-16 12:00:00")
    sealed = Tempfile.create([ "plain", ".zip" ], binmode: true) do |plain|
      plain.write(build_zip)
      plain.flush
      StringIO.new.binmode.tap { |out| Backup::Envelope.seal(plain.path, out, key: Backup::Key.parse(Backup::Key.generate), made_at: 1.year.from_now, metadata: {}) }.string
    end

    backup = upload_file(sealed) { |upload| Backup.import(upload) }

    assert_equal "zeropaper-2026-10-16-120000-uploaded.zpbackup", backup.filename
  end

  test "an upload made with this key has its chunks checked and is left to the restore to read" do
    name = put_sealed(build_zip, made_at: 1.day.ago)
    sealed = File.binread(File.join(@backup_dir, name))
    File.delete(File.join(@backup_dir, name))
    Archive::Reader.expects(:new).never

    backup = upload_file(sealed) { |upload| Backup.import(upload) }

    assert backup.filename.end_with?("-uploaded.zpbackup")
    assert backup.readable?
    assert backup.own_key?

    damaged = sealed.dup.tap { |bytes| bytes[-20] = (bytes[-20].ord ^ 1).chr }
    backup.remove!
    assert_raises(Archive::Reader::InvalidArchive) { upload_file(damaged) { |upload| Backup.import(upload) } }
    assert_empty Dir.children(@backup_dir)
  end

  test "an older export dated in the future or unreadably is named for now" do
    travel_to Time.zone.parse("2026-10-16 12:00:00")

    backup = upload_file(build_zip(manifest: { format: Archive::FORMAT, version: 1, exported_at: "2099-01-01T00:00:00Z" })) { |upload| Backup.import(upload) }
    assert_equal "zeropaper-2026-10-16-120000-uploaded.zpbackup", backup.filename
    backup.remove!

    backup = upload_file(build_zip(manifest: { format: Archive::FORMAT, version: 1, exported_at: "2026-99-99" })) { |upload| Backup.import(upload) }
    assert_equal "zeropaper-2026-10-16-120000-uploaded.zpbackup", backup.filename
  end

  test "uploads are checked against the size limits before anything is read from them" do
    Rails.configuration.x.stubs(:max_upload_bytes).returns(1.megabyte)
    bomb = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("manifest.json")
      zip.write({ format: Archive::FORMAT, version: Archive::VERSION }.to_json)
      zip.put_next_entry("documents/1/file/bomb.txt")
      zip.write("0" * 5.megabytes)
    end.string
    Zlib.expects(:crc32).never
    Digest::SHA256.expects(:new).never

    error = assert_raises(Archive::Reader::TooLarge) { upload_file(bomb) { |upload| Backup.import(upload) } }
    assert_equal "documents/1/file/bomb.txt unzips to more than the 4 MB limit.", error.message

    assert_empty Dir.children(@backup_dir)
  end

  test "an upload larger than the whole backup limit is refused" do
    Rails.configuration.x.stubs(:max_backup_bytes).returns(1.kilobyte)

    error = assert_raises(Archive::Reader::TooLarge) { upload_file(build_zip({ "documents/1/content.txt" => "x" * 2.kilobytes })) { |upload| Backup.import(upload) } }

    assert_match "backup limit (MAX_BACKUP_GB)", error.message
    assert_empty Dir.children(@backup_dir)
  end

  test "a zip with more entries or larger details than a backup can have is refused" do
    stub_const_entries = Archive::Reader::MAX_ENTRIES
    Zip::File.stubs(:count_entries).returns(stub_const_entries + 1)
    assert_raises(Archive::Reader::TooLarge) { upload_file(build_zip) { |upload| Backup.import(upload) } }
    Zip::File.unstub(:count_entries)

    details = build_zip({ "documents/1/document.json" => { title: "x" * Archive::Reader::MAX_DETAILS_BYTES }.to_json })
    error = assert_raises(Archive::Reader::TooLarge) { upload_file(details) { |upload| Backup.import(upload) } }
    assert_equal "documents/1/document.json unzips to more than the 4 MB limit.", error.message
  end

  test "an entry that inflates past the size it declares is refused" do
    text = "Amount due " * 1_000
    zip = Zip::OutputStream.write_buffer do |out|
      out.put_next_entry("manifest.json")
      out.write({ format: Archive::FORMAT, version: Archive::VERSION }.to_json)
      out.put_next_entry("notes.txt")
      out.write(text)
    end.string
    # Declare a smaller size in the local header and the central directory.
    assert_equal 2, zip.b.scan([ text.bytesize ].pack("V")).size
    zip = zip.b.gsub([ text.bytesize ].pack("V"), [ 4 ].pack("V"))

    error = assert_raises(Archive::Reader::InvalidArchive) { upload_file(zip) { |upload| Backup.import(upload) } }

    assert_equal "notes.txt is damaged.", error.message
  end
end
