class ConversationsController < ApplicationController
  before_action :set_conversation, only: %i[ show destroy ]
  rate_limit to: 20, within: 1.minute, only: :create, scope: "research", by: -> { Current.user.id },
    with: -> { redirect_to conversations_path, alert: "Too many questions. Wait a minute and ask again." }

  def index
    @conversations = Current.user.conversations.order(updated_at: :desc)
  end

  def show
    @conversations = Current.user.conversations.order(updated_at: :desc).limit(30)
  end

  def create
    question = params[:question].to_s.strip
    return redirect_to(conversations_path, alert: "Ask a question to start.") if question.blank?

    conversation = Current.user.conversations.create!(title: question.truncate(80))
    conversation.ask!(question)
    redirect_to conversation
  end

  def destroy
    @conversation.destroy
    redirect_to conversations_path, notice: "Conversation deleted.", status: :see_other
  end

  private
    def set_conversation
      @conversation = Current.user.conversations.find(params[:id])
    end
end
