require "test_helper"

class PasskeysMailerTest < ActionMailer::TestCase
  include EnvHelpers

  test "the passkey name is plain in the text part and escaped in the HTML part" do
    email = with_mail_from { PasskeysMailer.added(users(:one), "Tom & Jerry").message }

    assert_includes email.text_part.body.decoded, "“Tom & Jerry”"
    assert_includes email.html_part.body.decoded, "“Tom &amp; Jerry”"
  end
end
