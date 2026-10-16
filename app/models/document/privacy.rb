# A private document never leaves the machine: Outbound refuses it, its files
# sit on the encrypted disk service, and only local OCR, rules and embeddings
# touch it.
module Document::Privacy
  extend ActiveSupport::Concern

  ATTACHMENTS = %i[file original_file archive_file thumbnail].freeze

  included do
    scope :shareable, -> { where(private: false) }
    scope :private_only, -> { where(private: true) }
  end

  # Marks the document private and reprocesses it locally. Whatever a hosted
  # provider produced (summary, title, tags) is discarded, though what was
  # already sent cannot be recalled.
  def privatize!(reason:, reprocess: true)
    return if private?

    transaction do
      update!(private: true, private_reason: reason)
      move_attachments_to_current_service
      update!(summary: nil, ai_model: nil, metadata_source: nil) if metadata_source == "ai"
    end
    process_later if reprocess
  end

  def publicize!
    return unless private?

    transaction do
      update!(private: false, private_reason: nil)
      move_attachments_to_current_service
    end
    process_later
  end

  # Marks the document private without reprocessing. The pipeline uses this
  # when a local check finds a reason partway through, before anything has
  # been sent out.
  def privatize_during_processing!(reason)
    return if private?

    update!(private: true, private_reason: reason)
    move_attachments_to_current_service
  end

  # Runs the rules that mark documents private once the text is known.
  def screen_for_privacy(text)
    return if private? || text.blank?

    if (rule = Rule.where(mark_private: true).matching(self, text: text).first)
      privatize_during_processing!(rule.private_reason)
    end
  end

  def needs_privacy_screening?
    !private? && Rule.enabled.where(mark_private: true).exists?
  end

  private
    def move_attachments_to_current_service
      ATTACHMENTS.each do |name|
        attachment = public_send(name)
        next unless attachment.attached?
        next if attachment.blob.service_name == storage_service_name

        blob = attachment.blob
        attachment.attach(io: StringIO.new(blob.download), filename: blob.filename, content_type: blob.content_type)
      end
    end
end
