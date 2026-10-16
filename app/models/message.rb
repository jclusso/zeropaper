class Message < ApplicationRecord
  ROLES = %w[user assistant].freeze
  STATUSES = %w[streaming complete failed].freeze
  BROADCAST_INTERVAL = 0.25
  # An answer streaming longer than this with no live job behind it is
  # stuck, usually because its worker was killed by a restart.
  STUCK_AFTER = 10.minutes
  STUCK_MESSAGE = "The answer stopped unexpectedly, probably because the app restarted.".freeze

  class NotRetryable < StandardError; end

  belongs_to :conversation

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }

  scope :completed, -> { where(status: "complete") }

  def self.recover_stuck
    where(status: "streaming").where(updated_at: ...STUCK_AFTER.ago).find_each do |message|
      message.fail!(STUCK_MESSAGE) unless message.research_job_alive?
    end
  end

  def user?
    role == "user"
  end

  def streaming?
    status == "streaming"
  end

  # Only the latest answer can be asked again, so later turns never lose
  # the context they were answered with.
  def retryable?
    status == "failed" && !user? && conversation.messages.last == self
  end

  # Whether a queued or running job will still answer this message.
  def research_job_alive?
    research_jobs.any? { |job| !job.finished? && job.failed_execution.nil? }
  end

  # Answers once per attempt. A job that runs again after the answer
  # finished, failed or moved to a retry does nothing, and a rerun of the
  # same attempt starts from an empty answer so no text appears twice.
  def research!
    return unless streaming?

    update!(content: "", steps: [])
    Research.new(self).run
  end

  def retry!
    raise NotRetryable, "Only the latest answer that stopped can be retried." unless retryable?

    update!(status: "streaming", content: "", steps: [], cited_document_ids: [], private_match_ids: [])
    conversation.touch
    broadcast_now
    ResearchJob.perform_later(self)
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
    def research_jobs
      return [] unless defined?(SolidQueue::Job) && SolidQueue::Job.table_exists?

      SolidQueue::Job.where(concurrency_key: ResearchJob.new(self).concurrency_key, finished_at: nil)
    end

    def broadcast_now
      @last_broadcast_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Turbo::StreamsChannel.broadcast_replace_to(conversation, target: self, partial: "messages/message", locals: { message: self })
    end
end
