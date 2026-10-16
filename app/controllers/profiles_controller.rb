class ProfilesController < ApplicationController
  def show
    @user = Current.user
  end

  def update
    @user = Current.user
    if password_change? && !@user.authenticate(params[:user][:current_password].to_s)
      @user.errors.add(:current_password, "is incorrect")
      render :show, status: :unprocessable_entity
    elsif @user.update(profile_params)
      redirect_to profile_path, notice: "Profile saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def password_change?
      params.dig(:user, :password).present?
    end

    def profile_params
      permitted = params.expect(user: %i[ name email_address password password_confirmation theme ])
      permitted.delete(:theme) unless permitted[:theme].in?(ApplicationHelper::THEMES.keys)
      password_change? ? permitted : permitted.except(:password, :password_confirmation)
    end
end
