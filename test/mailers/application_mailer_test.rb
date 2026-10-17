require "test_helper"

class ApplicationMailerTest < ActionMailer::TestCase
  include EnvHelpers

  test "mail is deliverable once MAIL_FROM is set" do
    with_mail_from { assert ApplicationMailer.deliverable? }
  end

  test "without MAIL_FROM mail is off whatever the SMTP settings say" do
    ApplicationMailer.stubs(:delivery_method).returns(:smtp)
    ApplicationMailer.stubs(:smtp_settings).returns(address: "smtp.example.com", port: 587)

    with_env("MAIL_FROM" => nil) { refute ApplicationMailer.deliverable? }
    with_env("MAIL_FROM" => "") { refute ApplicationMailer.deliverable? }
  end

  test "SMTP on localhost counts as set up when MAIL_FROM is set" do
    ApplicationMailer.stubs(:delivery_method).returns(:smtp)
    ApplicationMailer.stubs(:smtp_settings).returns(address: "localhost", port: 25)

    with_mail_from { assert ApplicationMailer.deliverable? }
  end

  test "mail is off when deliveries are turned off" do
    ApplicationMailer.stubs(:perform_deliveries).returns(false)

    with_mail_from { refute ApplicationMailer.deliverable? }
  end

  test "in production mail is off until APP_URL or APP_HOST says where links point" do
    Rails.stubs(:env).returns(ActiveSupport::EnvironmentInquirer.new("production"))

    with_mail_from do
      with_env("APP_URL" => nil, "APP_HOST" => nil) { refute ApplicationMailer.deliverable? }
      with_env("APP_URL" => nil, "APP_HOST" => "docs.example.com") { assert ApplicationMailer.deliverable? }
      with_env("APP_URL" => "http://nas.local:3000", "APP_HOST" => nil) { assert ApplicationMailer.deliverable? }
    end
  end

  test "mail is sent from MAIL_FROM" do
    email = with_mail_from("ZeroPaper <paper@example.com>") { PasswordsMailer.reset(users(:one)).message }

    assert_equal [ "paper@example.com" ], email.from
    assert_equal "ZeroPaper <paper@example.com>", email[:from].value
  end
end
