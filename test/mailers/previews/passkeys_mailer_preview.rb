# Preview all emails at http://localhost:3000/rails/mailers/passkeys_mailer
class PasskeysMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/passkeys_mailer/added
  def added
    PasskeysMailer.added(User.take, "MacBook")
  end
end
