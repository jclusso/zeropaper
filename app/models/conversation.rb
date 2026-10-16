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

  # Completed messages before the given one that may go back to the model,
  # newest `limit` at most. A turn (a question and its answers) is left out
  # when an answer used a document that is private now; it stays on the page.
  def shareable_history(before:, limit:)
    earlier = messages.completed.where("id < ?", before.id).last(limit)
    private_ids = Document.private_only.where(id: earlier.flat_map(&:shared_document_ids)).pluck(:id).to_set

    earlier.slice_before(&:user?).reject { |turn| turn.any? { |message| message.shared_document_ids.any? { |id| private_ids.include?(id) } } }.flatten
  end
end
