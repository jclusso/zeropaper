class Conversations::Messages::RetriesController < ApplicationController
  # A retry asks the model again, so it counts toward the Research limit.
  rate_limit to: 20, within: 1.minute, scope: "research", by: -> { Current.user.id },
    with: -> { redirect_to conversation_path(params[:conversation_id]), alert: "Too many questions. Wait a minute and ask again." }

  def create
    message = Current.user.conversations.find(params[:conversation_id]).messages.find(params[:message_id])
    message.retry!
    redirect_to message.conversation
  rescue Message::NotRetryable => error
    redirect_to message.conversation, alert: error.message
  end
end
