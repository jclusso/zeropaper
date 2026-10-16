require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  include CableDisconnects

  setup { sign_in_as users(:one) }

  test "the theme is a profile setting rendered on the page" do
    get profile_path
    assert_select "html[data-theme=system]:not(.dark)"
    assert_select "input[type=radio][name='user[theme]']", count: 3

    patch profile_path, params: { user: { theme: "dark" } }
    assert_redirected_to profile_path
    assert_equal "dark", users(:one).reload.theme

    get documents_path
    assert_select "html.dark[data-theme=dark]"
  end

  test "appearance is the last box on the page" do
    get profile_path

    assert_select "section h2.section-title" do |titles|
      assert_equal "Appearance", titles.last.text
    end
  end

  test "changing the email address needs the current password" do
    patch profile_path, params: { user: { name: "Ada Admin", email_address: "attacker@example.com" } }

    assert_response :unprocessable_entity
    assert_equal "one@example.com", users(:one).reload.email_address
    assert_select ".text-danger, [role=alert], li", text: /Current password is needed to change your email or password/

    patch profile_path, params: { user: { name: "Ada Admin", email_address: "attacker@example.com", current_password: "wrong" } }
    assert_response :unprocessable_entity
    assert_equal "one@example.com", users(:one).reload.email_address
  end

  test "the email address changes with the current password" do
    patch profile_path, params: { user: { name: "Ada Admin", email_address: " Ada@Example.com ", current_password: "password" } }

    assert_redirected_to profile_path
    assert_equal "ada@example.com", users(:one).reload.email_address
  end

  test "saving the same email address and a new name needs no password" do
    patch profile_path, params: { user: { name: "Ada Lovelace", email_address: "ONE@example.com" } }

    assert_redirected_to profile_path
    assert_equal "Ada Lovelace", users(:one).reload.name
  end

  test "a new password needs the current one" do
    patch profile_path, params: { user: { email_address: "one@example.com", password: "new password", password_confirmation: "new password" } }

    assert_response :unprocessable_entity
    refute users(:one).reload.authenticate("new password")
  end

  test "a new password signs out every other session but this one" do
    other = users(:one).sessions.create!
    current = Current.session

    patch profile_path, params: { user: { email_address: "one@example.com", current_password: "password", password: "new password", password_confirmation: "new password" } }

    assert_redirected_to profile_path
    assert users(:one).reload.authenticate("new password")
    refute Session.exists?(other.id)
    assert Session.exists?(current.id)
    assert_equal 1, cable_disconnects(other)
    assert_equal 0, cable_disconnects(current)
    get profile_path
    assert_response :success
  end

  test "an unknown theme is ignored" do
    patch profile_path, params: { user: { theme: "neon" } }

    assert_equal "system", users(:one).reload.theme
  end

  test "there is no theme switcher in the navigation" do
    get documents_path

    assert_select "header [role=radiogroup]", count: 0
    assert_select "aside a[href='#{rules_path}']", text: /Rules/
  end
end
