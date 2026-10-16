class Message < ApplicationRecord
  ROLES = %w[user assistant].freeze
  STATUSES = %w[streaming complete failed].freeze
  BROADCAST_INTERVAL = 0.25

  belongs_to :conversation

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }

  scope :completed, -> { where(status: "complete") }

  def user?
    role == "user"
  end

  def streaming?
    status == "streaming"
  end

  def cited_documents
    Document.shareable.where(id: cited_document_ids).index_by(&:id)
  end

  # Every document the answer handed to the model. Answers from before this
  # was recorded only know the ones they cited.
  def shared_document_ids
    (used_document_ids + cited_document_ids.map(&:to_i)).uniq
  end

  def private_matches
    Document.private_only.where(id: private_match_ids)
  end

  def add_step!(label)
    update!(steps: steps + [ { "label" => label, "at" => Time.current.iso8601 } ])
    broadcast_now
  end

  def append!(text)
    return if text.blank?

    self.content += text
    if @last_broadcast_at.nil? || Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_broadcast_at > BROADCAST_INTERVAL
      save!
      broadcast_now
    end
  end

  def finish!(content:, cited_document_ids:, private_match_ids:, used_document_ids: cited_document_ids)
    update!(status: "complete", content: content, cited_document_ids: cited_document_ids, used_document_ids: used_document_ids,
      private_match_ids: private_match_ids)
    broadcast_now
  end

  def fail!(error)
    update!(status: "failed", content: [ content.presence, "Research stopped: #{error}" ].compact.join("\n\n"))
    broadcast_now
  end

  private
    def broadcast_now
      @last_broadcast_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Turbo::StreamsChannel.broadcast_replace_to(conversation, target: self, partial: "messages/message", locals: { message: self })
    end
end
