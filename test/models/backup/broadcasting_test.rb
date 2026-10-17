require "test_helper"
require "turbo/broadcastable/test_helper"

class Backup::BroadcastingTest < ActiveSupport::TestCase
  include BackupFolder
  include Turbo::Broadcastable::TestHelper

  test "a backup refreshes open Backups pages as it starts and finishes" do
    assert refreshes { Backup.create! }

    backup = Backup.create!
    assert refreshes { backup.process! }
    assert_equal "ready", backup.status, backup.error
  end

  test "uploading, syncing and removing backups refreshes open Backups pages" do
    assert refreshes { upload_file(build_zip) { |path| Backup.import(path) } }

    name = put_sealed(build_zip, made_at: 1.day.ago)
    assert refreshes { Backup.sync }
    refute refreshes { Backup.sync }

    File.delete(File.join(@backup_dir, name))
    assert refreshes { Backup.sync }

    assert refreshes { Backup.stored.sole.remove! }
  end

  test "a restore refreshes open Backups pages" do
    backup = Backup.create!
    backup.process!

    restore = nil
    assert refreshes { restore = Restore.create!(user: users(:one), filename: backup.filename) }
    assert refreshes { restore.process! }
    assert_equal "ready", restore.status, restore.error
  end

  private
    def refreshes(&block)
      broadcasts = capture_turbo_stream_broadcasts(Backup::STREAM) { perform_enqueued_jobs(only: Turbo::Streams::BroadcastStreamJob, &block) }
      broadcasts.any? { |stream| stream["action"] == "refresh" }
    end
end
