# A saved Research chat. Asking again resumes it with the earlier
# questions and answers as context.
class Conversation < ApplicationRecord
  belongs_to :user
  has_many :messages, -> { order(:created_at, :id) }, dependent: :delete_all

  validates :title, presence: true

  scope :recent, -> { order(updated_at: :desc) }

  def self.start!(user:, question:)
    conversation = user.conversations.create!(title: question.to_s.squish.truncate(80))
    conversation.ask!(question)
    conversation
  end

  def ask!(question)
    question = question.to_s.strip
    raise ArgumentError, "question is blank" if question.blank?

    transaction do
      messages.create!(role: "user", content: question)
      messages.create!(role: "assistant", status: "streaming")
    end.tap do |answer|
      touch
      ResearchJob.perform_later(answer)
    end
  end

  def busy?
    messages.exists?(status: "streaming")
  end

  # The earlier messages a new answer is given, and every document they
  # carry.
  History = Data.define(:messages, :document_ids)

  # Completed messages before the given one that may go back to the model,
  # newest `limit` at most. A turn (a question and its answers) is left out
  # when an answer carries a document that is private or deleted now, or
  # documents that are not known; it stays on the page.
  def shareable_history(before:, limit:)
    earlier = messages.completed.where("id < ?", before.id).to_a
    sources = sources_by_message(earlier)
    recent = earlier.last(limit)
    available = Document.shareable.where(id: recent.flat_map { |message| sources[message].to_a }).pluck(:id).to_set

    kept = recent.slice_before(&:user?).select { |turn| turn.all? { |message| sources[message]&.all? { |id| available.include?(id) } } }.flatten
    History.new(messages: kept, document_ids: kept.flat_map { |message| sources[message] }.uniq)
  end

  private
    # The documents behind each message, or nil when they are not known.
    # Answers now record all of them: what their tools returned and what the
    # history they were given carried. Older answers only recorded what
    # their own tools returned or what they cited, so each is taken to carry
    # every document the conversation used before it as well. An older answer
    # that recorded none, and every older answer after it, is unknown: it may
    # have read documents it never recorded.
    def sources_by_message(messages)
      seen = Set.new
      unknown = false
      messages.to_h do |message|
        own = message.shared_document_ids
        unknown ||= !message.user? && !message.provenance_complete? && own.empty?
        sources =
          if message.user? then []
          elsif message.provenance_complete? then own
          elsif !unknown then (seen | own).to_a
          end
        seen.merge(own).merge(sources.to_a)
        [ message, sources ]
      end
    end
end
