module Document::Reviewable
  extend ActiveSupport::Concern

  REASONS = {
    "always" => "New document",
    "low_confidence" => "Low-confidence details",
    "missing_details" => "Missing date or correspondent",
    "possible_duplicate" => "Possible duplicate",
    "blank_pages" => "Blank pages found",
    "ai_failed" => "AI extraction failed",
    "failed" => "Processing failed"
  }.freeze

  included do
    scope :in_inbox, -> { where(needs_review: true) }
  end

  def add_review_reason!(reason)
    return if review_reasons.include?(reason)

    update_columns(review_reasons: review_reasons + [ reason ], needs_review: true, updated_at: Time.current)
    broadcast_review_changes
  end

  def review_resolved!(reason)
    return unless review_reasons.include?(reason)

    remaining = review_reasons - [ reason ]
    update_columns(review_reasons: remaining, needs_review: remaining.any?, updated_at: Time.current)
    broadcast_review_changes
  end

  # Reasons settled by looking the document over. Blank pages, duplicates and
  # failures each have their own fix and are never cleared in bulk.
  CHECK_REASONS = %w[always low_confidence missing_details ai_failed].freeze

  def review_checked!
    remaining = review_reasons - CHECK_REASONS - stale_review_reasons
    update_columns(review_reasons: remaining, needs_review: remaining.any?, updated_at: Time.current)
    broadcast_review_changes
  end

  def only_needs_a_check?
    needs_review? && (review_reasons - CHECK_REASONS - stale_review_reasons).empty?
  end

  # Reasons whose problem is already gone, such as a duplicate whose original
  # was deleted.
  def stale_review_reasons
    [ ("possible_duplicate" if duplicate_of_id.nil?), ("blank_pages" if suggested_blank_pages.empty?),
      ("failed" unless status == "failed") ].compact & review_reasons
  end

  # Whether the AI added this document's correspondent while filing it, so
  # the reviewer can check a name nobody has seen before.
  def ai_created_correspondent?
    correspondent_id.present? && correspondent_id == ai_created_correspondent_id
  end

  def review_reason_labels
    review_reasons.map { |reason| REASONS.fetch(reason, reason.humanize) }
  end

  private
    def flag_for_review_after_processing
      review_resolved!("failed")
      add_review_reason!("always") if settings.always_require_review?
      if metadata_source == "ai" && confidence && confidence < settings.review_confidence_threshold
        add_review_reason!("low_confidence")
      end
      if metadata_source == "rules" && (document_date.nil? || correspondent.nil?)
        add_review_reason!("missing_details")
      end
    end
end
