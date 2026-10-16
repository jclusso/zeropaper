class ProfilesController < ApplicationController
  def show
    @user = Current.user
  end

  def update
    @user = Current.user
    if credential_change? && !@user.authenticate(params[:user][:current_password].to_s)
      @user.errors.add(:current_password, params[:user][:current_password].blank? ? "is needed to change your email or password" : "is incorrect")
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

    # The email address can reset the password, so changing it needs the
    # current password too.
    def credential_change?
      email = params.dig(:user, :email_address)
      password_change? || (!email.nil? && User.normalize_value_for(:email_address, email.to_s) != @user.email_address)
    end

    def profile_params
      permitted = params.expect(user: %i[ name email_address password password_confirmation theme ])
      permitted.delete(:theme) unless permitted[:theme].in?(ApplicationHelper::THEMES.keys)
      password_change? ? permitted : permitted.except(:password, :password_confirmation)
    end
end
