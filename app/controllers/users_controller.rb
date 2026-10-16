class UsersController < ApplicationController
  layout "admin"

  require_admin
  before_action :set_user, only: %i[ edit update destroy ]

  def index
    @users = User.alphabetically
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to users_path, notice: "#{@user.name} can now sign in."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attributes = user_params
    attributes = attributes.except(:password, :password_confirmation) if attributes[:password].blank?
    if @user.last_admin? && attributes[:admin] == "0"
      @user.errors.add(:admin, "cannot be removed from the last admin")
      render :edit, status: :unprocessable_entity
    elsif @user.update(attributes)
      redirect_to users_path, notice: "#{@user.name} saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @user == Current.user || @user.last_admin?
      redirect_to users_path, alert: "You cannot delete yourself or the last admin."
    else
      @user.destroy
      redirect_to users_path, notice: "#{@user.name} removed.", status: :see_other
    end
  end

  private
    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.expect(user: %i[ name email_address password password_confirmation admin ])
    end
end
