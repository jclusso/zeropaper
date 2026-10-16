require "test_helper"

class CorrespondentsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "creates a correspondent with auto-match and private documents" do
    get new_correspondent_path
    assert_select "input[type=checkbox][name='correspondent[auto_match]']"

    post correspondents_path, params: { correspondent: { name: "City Hospital", auto_match: "1", private_documents: "1" } }

    correspondent = Correspondent.named("City Hospital")
    assert_redirected_to correspondents_path
    assert correspondent.auto_match?
    assert correspondent.private_documents?
  end

  test "turns auto-match off" do
    patch correspondent_path(correspondents(:acme_power)), params: { correspondent: { auto_match: "0" } }

    refute correspondents(:acme_power).reload.auto_match?
  end
end
