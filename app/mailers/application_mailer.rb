class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"

  # Whether outgoing mail has been set up. Out of the box, production would
  # hand mail to an SMTP server on localhost that is usually not there.
  def self.deliverable?
    perform_deliveries && (delivery_method != :smtp || smtp_settings[:address].to_s.then { |address| address.present? && address != "localhost" })
  end
end
