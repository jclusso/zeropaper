# Loads an export zip. Documents already in the library (same checksum) are
# skipped; restored ones keep their text and details and are only re-indexed
# locally, so nothing is sent out.
class Restore < ApplicationRecord
  STATUSES = %w[pending processing ready failed].freeze

  belongs_to :user
  has_one_attached :archive, service: ->(_restore) { "#{ActiveStorage::Blob.service.name}_private" }

  validates :status, inclusion: { in: STATUSES }
  validate :archive_is_zip, on: :create

  scope :recent, -> { order(created_at: :desc) }

  def process_later
    RestoreJob.perform_later(self)
  end

  def process!
    update!(status: "processing", error: nil)
    archive.open do |file|
      Archive::Reader.new(file.path, restored_by: user).each_result do |result|
        increment!(result == :restored ? :restored_count : :skipped_count)
      end
    end
    archive.purge_later
    update!(status: "ready")
  rescue StandardError => error
    update!(status: "failed", error: error.message.truncate(1_000))
  end

  private
    def archive_is_zip
      errors.add(:archive, "must be a ZeroPaper export (.zip)") unless archive.attached? && archive.content_type == "application/zip"
    end
end
