# A zip of the whole library: files, OCR text, details, thumbnails and
# taxonomy, restorable into this or another instance. Kept on the encrypted
# service because it may hold private documents.
class Export < ApplicationRecord
  STATUSES = %w[pending processing ready failed].freeze

  belongs_to :user
  has_one_attached :archive, service: ->(_export) { "#{ActiveStorage::Blob.service.name}_private" }

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def process_later
    ExportJob.perform_later(self)
  end

  def process!
    update!(status: "processing", error: nil)
    scope = include_private? ? Document.all : Document.shareable

    Dir.mktmpdir do |dir|
      path = File.join(dir, "export.zip")
      Archive::Writer.new(scope, include_private: include_private?).write(path)
      archive.attach(io: File.open(path), filename: filename, content_type: "application/zip")
    end
    update!(status: "ready", documents_count: scope.count)
  rescue StandardError => error
    update!(status: "failed", error: error.message.truncate(1_000))
  end

  def filename
    "zeropaper-#{created_at.strftime("%Y-%m-%d-%H%M")}.zip"
  end
end
