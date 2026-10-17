require "test_helper"

class BackupsControllerTest < ActionDispatch::IntegrationTest
  include BackupFolder

  setup { sign_in_as users(:one) }

  test "saves the schedule" do
    patch backups_schedule_path, params: { setting: { backup_enabled: "1", backup_frequency: "weekly", backup_keep_daily: "0", backup_keep_weekly: "8", backup_keep_monthly: "6", backup_keep_yearly: "3" } }

    assert_redirected_to backups_path
    setting = Setting.instance.reload
    assert setting.backup_enabled?
    assert_equal 1.week, setting.backup_interval
    assert_equal [ 0, 8, 6, 3 ], [ setting.backup_keep_daily, setting.backup_keep_weekly, setting.backup_keep_monthly, setting.backup_keep_yearly ]
  end

  test "the schedule fields are locked until backing up automatically is on" do
    get backups_path
    assert_select "fieldset[data-gate-target='gated'][disabled] input[name='setting[backup_keep_monthly]']"

    Setting.instance.update!(backup_enabled: true)
    get backups_path
    assert_select "fieldset[data-gate-target='gated']:not([disabled]) input[name='setting[backup_keep_monthly]']"
  end

  test "backs up now, then lists, downloads and deletes the backup" do
    perform_enqueued_jobs { post backups_path }

    backup = Backup.last
    assert_equal users(:one), backup.user
    assert_equal "ready", backup.status, backup.error

    get backups_path
    assert_select "td", text: /#{backup.filename}/
    assert_select "td", text: /0 documents · #{users(:one).name}/
    assert_select "form[action='#{backup_restoration_path(backup)}'] input[name=backup_key]", count: 0

    get backup_path(backup)
    assert_response :success
    assert_equal Backup::Envelope::MAGIC, response.body.byteslice(0, 8)

    delete backup_path(backup)
    assert_redirected_to backups_path
    assert_empty Backup.files
    assert_empty Backup.stored
  end

  test "asks to download the key until it is, and the key file restores" do
    get backups_path
    assert_select "a[href='#{backups_key_path}']", count: 2
    assert_select "#key", text: /Not downloaded yet/

    get backups_key_path
    assert_response :success
    assert_equal "#{Backup::Key.encode(Setting.instance.reload.backup_key_bytes)}\n", response.body
    assert_match 'filename="zeropaper.key"', response.headers["Content-Disposition"]
    assert Setting.instance.backup_key_downloaded_at

    get backups_path
    assert_select "a[href='#{backups_key_path}']", count: 1
    assert_select "#key", text: /Last downloaded/
  end

  test "a failed backup shows its error in a tooltip" do
    Backup.create!(user: users(:one), status: "failed", error: "The backup folder is not writable by ZeroPaper.")

    get backups_path

    assert_select "[role=tooltip]", text: "The backup folder is not writable by ZeroPaper."
  end

  test "a failed backup can be deleted, but a running one cannot" do
    failed = Backup.create!(user: users(:one), status: "failed", error: "NAS offline")
    running = Backup.create!(user: users(:one), status: "processing")

    get backups_path
    assert_select "form[action='#{backup_path(failed)}'] button[aria-label='Delete failed backup']"
    assert_select "form[action='#{backup_path(running)}']", count: 0

    delete backup_path(failed)
    assert_redirected_to backups_path
    refute Backup.exists?(failed.id)

    delete backup_path(running)
    assert Backup.exists?(running.id)
  end

  test "restores a backup from the folder" do
    name = put_sealed(build_zip)
    Backup.record_existing_files

    post backup_restoration_path(Backup.stored.sole)

    assert_redirected_to backups_path(anchor: "restores")
    assert_equal name, Restore.last.filename
  end

  test "a restore run by a deleted user still lists" do
    restore = Restore.new(user: users(:two), filename: "zeropaper-2026-01-01-030000.zpbackup", status: "ready")
    restore.save!(validate: false)
    users(:two).destroy!

    get backups_path

    assert_response :success
    assert_match "Deleted user", response.body
  end

  test "a backup made with another key asks for it" do
    other = Backup::Key.generate
    put_sealed(build_zip, key: Backup::Key.parse(other))
    Backup.record_existing_files
    id = Backup.stored.sole.id

    get backups_path
    assert_select "td", text: /Made with key #{Backup::Key.id(Backup::Key.parse(other))}/
    assert_select "form[action='#{backup_restoration_path(id)}'] input[name=backup_key]"

    post backup_restoration_path(id)
    assert_equal "Key is not the key this backup was made with", flash[:alert]

    post backup_restoration_path(id), params: { backup_key: other }
    assert_redirected_to backups_path(anchor: "restores")
  end

  test "a pasted backup key never reaches the log" do
    other = Backup::Key.generate
    put_sealed(build_zip, key: Backup::Key.parse(other))
    Backup.record_existing_files
    id = Backup.stored.sole.id
    log = StringIO.new
    previous = ActionController::Base.logger
    ActionController::Base.logger = ActiveSupport::Logger.new(log)

    post backup_restoration_path(id), params: { backup_key: other }
    assert_redirected_to backups_path(anchor: "restores")
    # The old field name, from a page loaded before an upgrade.
    post backup_restoration_path(id), params: { key: other }

    assert_match %(Parameters: {"backup_key" => "[FILTERED]"), log.string
    assert_match %(Parameters: {"key" => "[FILTERED]"), log.string
    refute_includes log.string, other
    refute_includes log.string, other.delete_prefix("zpkey-")
  ensure
    ActionController::Base.logger = previous
  end

  test "malformed files in the folder are listed as unreadable and the page still loads" do
    [ "[1]", { version: 1, made_at: "2026-99-99T00:00:00Z", key_id: "abcd1234", nonce: "AAAA" }.to_json ].each_with_index do |header, index|
      put_backup(Backup::Envelope::MAGIC + [ header.bytesize ].pack("N") + header, "zeropaper-2026-01-0#{index + 1}-000000.zpbackup")
    end
    put_sealed(build_zip, made_at: 1.day.ago)
    Backup.record_existing_files

    get backups_path

    assert_response :success
    assert_select "td span.text-danger", text: "Cannot be read", count: 2
    assert_select "td", text: /0 documents/, count: 0
  end

  test "an upload with a crafted header is refused with a message" do
    header = { version: 1, made_at: "2026-99-99T00:00:00Z", key_id: "abcd1234", nonce: "AAAA" }.to_json
    upload = Rack::Test::UploadedFile.new(StringIO.new(Backup::Envelope::MAGIC + [ header.bytesize ].pack("N") + header), "application/octet-stream", true, original_filename: "x.zpbackup")

    post backups_uploads_path, params: { archive: upload }

    assert_redirected_to backups_path
    assert_equal "This backup is damaged.", flash[:alert]
    assert_empty Backup.files
  end

  test "an upload that unzips past the limit is refused before it is read" do
    Rails.configuration.x.stubs(:max_upload_bytes).returns(1.megabyte)
    bomb = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("manifest.json")
      zip.write({ format: Archive::FORMAT, version: Archive::VERSION }.to_json)
      zip.put_next_entry("documents/1/file/bomb.txt")
      zip.write("0" * 5.megabytes)
    end.string
    Zlib.expects(:crc32).never

    post backups_uploads_path, params: { archive: Rack::Test::UploadedFile.new(StringIO.new(bomb), "application/zip", true, original_filename: "old.zip") }

    assert_redirected_to backups_path
    assert_equal "documents/1/file/bomb.txt unzips to more than the 4 MB limit.", flash[:alert]
    assert_empty Backup.files
  end

  test "an upload missing a document's details is refused with a message" do
    zip = build_zip({ "documents/1/content.txt" => "", "documents/1/file/a.txt" => "x" })

    post backups_uploads_path, params: { archive: Rack::Test::UploadedFile.new(StringIO.new(zip), "application/zip", true, original_filename: "old.zip") }

    assert_equal "documents/1/document.json is missing", flash[:alert]
    assert_empty Backup.files
  end

  test "a restore whose backup unzips past the limit fails in its job before reading anything" do
    Rails.configuration.x.stubs(:max_upload_bytes).returns(1.megabyte)
    other = Backup::Key.generate
    put_sealed(Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("manifest.json")
      zip.write({ format: Archive::FORMAT, version: Archive::VERSION }.to_json)
      zip.put_next_entry("documents/1/file/bomb.txt")
      zip.write("0" * 5.megabytes)
    end.string, key: Backup::Key.parse(other))
    Backup.record_existing_files
    Zlib.expects(:crc32).never

    perform_enqueued_jobs { post backup_restoration_path(Backup.stored.sole), params: { backup_key: other } }

    restore = Restore.last
    assert_equal "failed", restore.status
    assert_equal "documents/1/file/bomb.txt unzips to more than the 4 MB limit.", restore.error
  end

  test "an uploaded backup is marked as uploaded and can be downloaded" do
    upload = Rack::Test::UploadedFile.new(StringIO.new(build_zip), "application/zip", true, original_filename: "old.zip")
    post backups_uploads_path, params: { archive: upload }
    backup = Backup.stored.sole
    assert backup.uploaded
    assert backup.filename.end_with?("-uploaded.zpbackup")

    get backup_path(backup)

    assert_response :success
    assert_equal Backup.files.sole.binread, response.body
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_match "attachment", response.headers["Content-Disposition"]
  end

  test "a backup whose file is gone is marked missing, not served, and can still be deleted" do
    name = put_sealed(build_zip)
    Backup.record_existing_files
    backup = Backup.stored.sole
    File.delete(File.join(@backup_dir, name))

    get backup_path(backup)
    assert_redirected_to backups_path
    assert_equal "#{name} is missing from the backup folder.", flash[:alert]

    get backups_path
    assert_select "td span.text-danger", text: "File missing"
    assert_select "form[action='#{backup_restoration_path(backup)}']", count: 0

    delete backup_path(backup)
    refute Backup.exists?(backup.id)
  end

  test "while the folder cannot be reached a backup is not served or deleted" do
    put_sealed(build_zip)
    Backup.record_existing_files
    backup = Backup.stored.sole
    unmounted

    get backup_path(backup)
    assert_equal Backup.unreachable_message, flash[:alert]

    delete backup_path(backup)
    assert_equal Backup.unreachable_message, flash[:alert]
    assert Backup.exists?(backup.id)
    refute backup.reload.missing?
  ensure
    mounted
  end

  test "a name outside the folder listing is not restored or served" do
    assert_no_difference -> { Restore.count } do
      post backup_restoration_path("master")
    end
    assert_redirected_to backups_path

    get backup_path("zeropaper-2026-01-01-030000")
    assert_redirected_to backups_path

    put_backup("x", "zeropaper-2026-01-01-030000.zpbackup")
    get backup_path(Backup.create!(status: "ready", filename: "../zeropaper-2026-01-01-030000.zpbackup"))
    assert_redirected_to backups_path
  end

  test "an uploaded export is encrypted into the folder" do
    upload = Rack::Test::UploadedFile.new(StringIO.new(build_zip), "application/zip", true, original_filename: "old.zip")

    post backups_uploads_path, params: { archive: upload }

    assert_redirected_to backups_path
    assert_equal 1, Backup.files.size
    assert Backup::Envelope.backup?(Backup.files.first)
    assert_equal Backup.files.first.basename.to_s, Backup.stored.sole.filename
  end

  test "an upload that is not a backup is refused" do
    upload = Rack::Test::UploadedFile.new(StringIO.new("hello"), "application/zip", original_filename: "fake.zip")

    post backups_uploads_path, params: { archive: upload }

    assert_equal "That file is not a ZeroPaper backup.", flash[:alert]
    assert_empty Backup.files
  end

  test "old export and restore links go to backups" do
    get "/exports"
    assert_redirected_to "/backups"

    get "/restores/new"
    assert_redirected_to "/backups"
  end
end
