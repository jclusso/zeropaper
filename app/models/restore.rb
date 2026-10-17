# Loads a backup from the backup folder. The backup is decrypted and checked
# in full before anything is restored. Documents already in the library (same
# checksum) are skipped; restored ones keep their text and details and are
# only re-indexed locally, so nothing is sent out.
#
# A backup made with another key, such as one from a previous install, is
# restored with that key, which is kept only until the restore finishes.
class Restore < ApplicationRecord
  include RunsAlone

  STATUSES = %w[pending processing ready failed].freeze

  belongs_to :user, optional: true

  encrypts :key

  validates :status, inclusion: { in: STATUSES }
  validate :backup_can_be_opened, on: :create

  scope :recent, -> { order(created_at: :desc) }

  after_commit -> { Backup.broadcast_changes }

  def process_later
    RestoreJob.perform_later(self)
  end

  # Runs once per restore, however often its job does.
  def process!
    run_alone do
      update!(status: "processing", error: nil)
      path = backup_file or raise(Backup.reachable? ? "#{filename} is missing from the backup folder." : Backup.unreachable_message)

      Backup.open_zip(path, key_bytes) do |zip|
        reader = Archive::Reader.new(zip, restored_by: user, own_key: key_bytes == Setting.instance.backup_key_bytes)
        reader.verify!
        reader.each_result do |result|
          increment!(result == :restored ? :restored_count : :skipped_count)
          Backup.broadcast_changes
        end
      end
      update!(status: "ready", key: nil)
    end
  rescue StandardError => error
    update!(status: "failed", error: error.message.truncate(1_000), key: nil)
  end

  private
    def backup_file
      Backup.stored.find_by(filename: filename)&.find_file
    end

    def key_bytes
      Backup::Key.parse(key) || Setting.instance.backup_key_bytes
    end

    def backup_can_be_opened
      path = backup_file
      if !Backup.stored.exists?(filename: filename)
        errors.add(:filename, "is not a listed backup")
      elsif path.nil?
        errors.add(:base, Backup.reachable? ? "#{filename} is missing from the backup folder." : Backup.unreachable_message)
      elsif key.present? && Backup::Key.parse(key).nil?
        errors.add(:key, "is not a ZeroPaper backup key")
      elsif Backup::Envelope.new(path.to_s).key_id != Backup::Key.id(key_bytes)
        errors.add(:key, "is not the key this backup was made with")
      end
    rescue Archive::Reader::InvalidArchive => error
      errors.add(:filename, error.message)
    end
end
