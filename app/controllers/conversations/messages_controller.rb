class Conversations::MessagesController < ApplicationController
  before_action :set_conversation

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
