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

  # Marks the document private and reprocesses it locally. Details a hosted
  # provider already returned (title, summary, correspondent, type, date,
  # tags) are kept, since clearing them recalls nothing; nothing more is
  # sent. Resetting the run stops any run in progress before its next
  # request.
  def privatize!(reason:, reprocess: true)
    return if private?

    transaction do
      update!(private: true, private_reason: reason)
      move_attachments_to_current_service
    end
    process_later if reprocess
  end

  # Makes the document shareable and reprocesses it, which can send it to
  # the AI providers in Settings. Refused, with the reason in errors, while
  # a filename or source rule still marks it private.
  def publicize!
    return true unless private?

    if (rule = private_rule_before_content)
      errors.add(:base, "The rule “#{rule.name}” still marks this document private. Change or turn off the rule first.")
      return false
    end

    transaction do
      update!(private: false, private_reason: nil)
      move_attachments_to_current_service
    end
    process_later
    true
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

  # Runs the filename and source rules, which can decide before any text is
  # read. Ingest already ran them, but rules may have changed since.
  def screen_before_content
    return if private?

    if (rule = private_rule_before_content)
      privatize_during_processing!(rule.private_reason)
    end
  end

  # Whether a content rule could still make this document private once its
  # text is read. Filename and source rules ran before processing started.
  def needs_privacy_screening?
    !private? && Rule.enabled.where(mark_private: true).any?(&:needs_content?)
  end

  private
    def private_rule_before_content
      Rule.where(mark_private: true).matching_before_content(self).first
    end

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
