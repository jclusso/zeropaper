require "test_helper"

class SettingIngestTest < ActiveSupport::TestCase
  test "the folder is INGEST_DIR" do
    settings = Setting.instance

    assert_equal Rails.configuration.x.ingest_dir, settings.ingest_path
    assert_equal File.join(Rails.configuration.x.ingest_dir, "private"), settings.private_ingest_path
    assert_equal Rails.configuration.x.ingest_dir, Ingest::Folder.new.root.to_s
  end

  test "the folder is not scanned when watching is off" do
    Setting.instance.update!(ingest_enabled: false)
    Ingest::Folder.any_instance.expects(:scan).never

    IngestFolderJob.perform_now

    refute Setting.instance.ingest_enabled?
  end
end
