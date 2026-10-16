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
end
