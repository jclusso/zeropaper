require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
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
