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

  test "deleting a user keeps their backups and restores without them" do
    user = users(:two)
    backup = Backup.create!(user: user)
    restore = Restore.new(user: user, filename: "zeropaper-2026-01-01-030000.zpbackup")
    restore.save!(validate: false)

    user.destroy!

    assert_nil backup.reload.user
    assert_nil restore.reload.user
  end
end
