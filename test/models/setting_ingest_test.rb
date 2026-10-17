require "test_helper"

class SettingIngestTest < ActiveSupport::TestCase
  test "the folder is INGEST_DIR" do
    settings = Setting.instance

    assert_equal Rails.configuration.x.ingest_dir, settings.ingest_path
    assert_equal File.join(Rails.configuration.x.ingest_dir, "private"), settings.private_ingest_path
    assert_equal Rails.configuration.x.ingest_dir, Ingest::Folder.new.root.to_s
  end

  test "the folder is not scanned when watching is off" do
    Dir.mktmpdir do |dir|
      file = Pathname(dir).join("statement.txt")
      file.write(BILL_TEXT)
      File.utime(1.minute.ago.to_time, 1.minute.ago.to_time, file)
      Rails.configuration.x.stubs(:ingest_dir).returns(dir)

      Setting.instance.update!(ingest_enabled: false)
      assert_no_difference -> { Document.count } do
        IngestFolderJob.perform_now
      end
      assert file.exist?

      Setting.instance.update!(ingest_enabled: true)
      assert_difference -> { Document.count } do
        IngestFolderJob.perform_now
      end
      refute file.exist?
    end
  end
end
