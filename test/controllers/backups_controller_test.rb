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
    id = backup.filename.delete_suffix(Backup::EXTENSION)

    get backups_path
    assert_select "td", text: /#{backup.filename}/
    assert_select "td", text: /0 documents · #{users(:one).name}/
    assert_select "form[action='#{backup_restoration_path(id)}'] input[name=key]", count: 0

    get backup_path(id)
    assert_response :success
    assert_equal Backup::Envelope::MAGIC, response.body.byteslice(0, 8)

    delete backup_path(id)
    assert_redirected_to backups_path
    assert_empty Backup.files
  end

  test "asks to download the key until it is, and the key file restores" do
    get backups_path
    assert_select "a[href='#{backups_key_path}']", count: 2
    assert_select "#key", text: /Not downloaded yet/

    get backups_key_path
    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_equal Setting.instance.reload.backup_key_bytes, Backup::Key.parse(response.body)
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

  test "restores a backup from the folder" do
    name = put_sealed(build_zip)

    post backup_restoration_path(name.delete_suffix(Backup::EXTENSION))

    assert_redirected_to backups_path(anchor: "restores")
    assert_equal name, Restore.last.filename
  end

  test "a backup made with another key asks for it" do
    other = Backup::Key.generate
    name = put_sealed(build_zip, key: Backup::Key.parse(other))
    id = name.delete_suffix(Backup::EXTENSION)

    get backups_path
    assert_select "td", text: /Made with key #{Backup::Key.id(Backup::Key.parse(other))}/
    assert_select "form[action='#{backup_restoration_path(id)}'] input[name=key]"

    post backup_restoration_path(id)
    assert_equal "Key is not the key this backup was made with", flash[:alert]

    post backup_restoration_path(id), params: { key: other }
    assert_redirected_to backups_path(anchor: "restores")
  end

  test "a name outside the folder listing is not restored or served" do
    assert_no_difference -> { Restore.count } do
      post backup_restoration_path("master")
    end
    assert_redirected_to backups_path

    get backup_path("zeropaper-2026-01-01-030000")
    assert_redirected_to backups_path
  end

  test "an uploaded export is encrypted into the folder" do
    upload = Rack::Test::UploadedFile.new(StringIO.new(build_zip), "application/zip", true, original_filename: "old.zip")

    post backups_uploads_path, params: { archive: upload }

    assert_redirected_to backups_path
    assert_equal 1, Backup.files.size
    assert Backup::Envelope.backup?(Backup.files.first)
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
