class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV["MAIL_FROM"] }
  layout "mailer"

  # Whether outgoing mail has been set up. Without MAIL_FROM there is no
  # sender to use, so mail counts as off whatever the SMTP settings say. In
  # production the links in mail need APP_URL or APP_HOST to point anywhere.
  def self.deliverable?
    ENV["MAIL_FROM"].present? && perform_deliveries && delivery_method.present? &&
      (AppUrl.known? || !Rails.env.production?)
  end
end
