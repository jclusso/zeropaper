# Keeps open pages current without a reload. A document's page follows its
# own changes, pages listing documents refresh when any document is added,
# changed or removed, and the Inbox count in the sidebar follows on every
# page. Saves made with update_columns skip callbacks, so they broadcast
# themselves.
module Document::Broadcasting
  extend ActiveSupport::Concern

  LIBRARY_STREAM = :documents
  INBOX_COUNT_STREAM = :inbox_count

  included do
    # Refreshes the document's page, and LIBRARY_STREAM when one is created.
    broadcasts_refreshes LIBRARY_STREAM

    after_update_commit -> { broadcast_refresh_later_to LIBRARY_STREAM }
    after_destroy_commit -> { broadcast_refresh_later_to LIBRARY_STREAM }
    after_save_commit :broadcast_inbox_count, if: :saved_change_to_needs_review?
    after_destroy_commit :broadcast_inbox_count, if: :needs_review?
  end

  class_methods do
    def broadcast_inbox_count
      Turbo::StreamsChannel.broadcast_replace_later_to INBOX_COUNT_STREAM, target: "inbox_count", partial: "layouts/inbox_count"
    end
  end

  def broadcast_changes
    broadcast_refresh_later
    broadcast_refresh_later_to LIBRARY_STREAM
  end

  private
    def broadcast_review_changes
      broadcast_changes
      broadcast_inbox_count
    end

    def broadcast_inbox_count
      self.class.broadcast_inbox_count
    end
end
