class Conversations::MessagesController < ApplicationController
  before_action :set_conversation
  rate_limit to: 20, within: 1.minute, only: :create, scope: "research", by: -> { Current.user.id },
    with: -> { redirect_to @conversation, alert: "Too many questions. Wait a minute and ask again." }

  def create
    question = params[:question].to_s.strip
    if question.blank?
      redirect_to @conversation
    elsif @conversation.messages.exists?(status: "streaming")
      redirect_to @conversation, alert: "Wait for the current answer to finish."
    else
      @conversation.ask!(question)
      redirect_to @conversation
    end
  end

  private
    def set_conversation
      @conversation = Current.user.conversations.find(params[:conversation_id])
    end
end
