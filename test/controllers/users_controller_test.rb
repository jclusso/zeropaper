require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @member = users(:two)
    2.times { @member.sessions.create! }
  end

  test "an admin setting a new password signs the user out everywhere" do
    patch user_path(@member), params: { user: { name: @member.name, email_address: @member.email_address, password: "new password", password_confirmation: "new password" } }

    assert_redirected_to users_path
    assert @member.reload.authenticate("new password")
    assert_empty @member.sessions
    assert_equal 1, users(:one).sessions.count, "the admin stays signed in"
  end

  test "saving without a new password keeps the user's sessions" do
    patch user_path(@member), params: { user: { name: "Bea Renamed", email_address: @member.email_address, password: "", password_confirmation: "" } }

    assert_redirected_to users_path
    assert_equal "Bea Renamed", @member.reload.name
    assert_equal 2, @member.sessions.count
  end
end
