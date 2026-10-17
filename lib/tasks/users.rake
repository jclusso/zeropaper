namespace :users do
  desc "Print a one-time password reset link for EMAIL, for when outgoing mail is not set up"
  task reset_password: :environment do
    email = ENV["EMAIL"].to_s.strip
    abort "Give the account's email address: bin/rails users:reset_password EMAIL=someone@example.com" if email.blank?

    user = User.find_by(email_address: email)
    abort "No user has the email address #{email}." unless user

    link = PasswordResetLink.new(user)
    if url = link.url
      puts "Open this link to choose a new password for #{user.email_address}. It works once and expires in #{link.expires_in.inspect}:"
      puts url
    else
      puts "Open this path on the app's address (for example https://docs.example.com) to choose a new password for #{user.email_address}. It works once and expires in #{link.expires_in.inspect}:"
      puts link.path
      puts "Set APP_URL or APP_HOST to print the full link."
    end
  end
end
