require "test_helper"

class SettingIngestTest < ActiveSupport::TestCase
  test "the folder defaults to INGEST_DIR and can be changed" do
    settings = Setting.instance
    assert_equal Rails.configuration.x.ingest_dir, settings.ingest_path

    Dir.mktmpdir do |dir|
      settings.update!(ingest_dir: " #{dir} ")
      assert_equal dir, settings.ingest_path
      assert_equal File.join(dir, "private"), settings.private_ingest_path
      assert_equal dir, Ingest::Folder.new.root.to_s
    end
  end

  test "a folder that does not exist is refused" do
    settings = Setting.instance

    refute settings.update(ingest_dir: "/nowhere/zeropaper-ingest")
    assert_includes settings.errors[:ingest_dir], "does not exist on this machine"
  end

  test "the folder is not scanned when watching is off" do
    Setting.instance.update!(ingest_enabled: false)
    Ingest::Folder.any_instance.expects(:scan).never

    IngestFolderJob.perform_now

    refute Setting.instance.ingest_enabled?
  end
end
