# The reset link an admin hands someone when mail is off. It uses the same
# token as the emailed link, so it expires the same way and stops working
# once the password changes.
class PasswordResetLink
  include Rails.application.routes.url_helpers

  attr_reader :user

  def initialize(user)
    @user = user
  end

  def path
    edit_password_path(user.password_reset_token)
  end

  # The full link, or nil when the app's address is not known.
  def url
    edit_password_url(user.password_reset_token, **link_options) if link_options[:host]
  end

  def expires_in
    ActiveSupport::Duration.build(user.password_reset_token_expires_in)
  end

  private
    # APP_URL or APP_HOST, and outside production the mailer's host.
    def link_options
      @link_options ||= AppUrl.url_options(ssl: ssl?).presence ||
        (Rails.env.production? ? {} : Rails.application.config.action_mailer.default_url_options || {})
    end

    def ssl?
      Rails.application.config.force_ssl || Rails.application.config.assume_ssl
    end
end
