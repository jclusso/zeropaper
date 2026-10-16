class SetupsController < ApplicationController
  allow_before_setup
  allow_unauthenticated_access
  before_action :require_first_run
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_setup_path, alert: "Try again later." }

  layout "authentication"

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params.merge(admin: true))

    if @user.save
      start_new_session_for @user
      redirect_to setup_ai_choice_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def require_first_run
      redirect_to root_path unless User.first_run?
    end

    def user_params
      params.expect(user: %i[ name email_address password password_confirmation ])
    end
end
