require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "passwords need at least 8 characters" do
    user = User.new(name: "Sam", email_address: "sam@example.com", password: "1234567")
    refute user.valid?
    assert_includes user.errors[:password], "is too short (minimum is 8 characters)"

    user.password = "12345678"
    assert user.valid?
  end
end
