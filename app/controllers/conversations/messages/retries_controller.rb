class Conversations::Messages::RetriesController < ApplicationController
  def create
    message = Current.user.conversations.find(params[:conversation_id]).messages.find(params[:message_id])
    message.retry!
    redirect_to message.conversation
  rescue Message::NotRetryable => error
    redirect_to message.conversation, alert: error.message
  end
end
