class PasskeysMailer < ApplicationMailer
  def added(user, name)
    @user = user
    @name = name
    mail subject: "A passkey was added to your account", to: user.email_address
  end
end
