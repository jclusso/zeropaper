require "test_helper"

class TitleCaseTest < ActionView::TestCase
  include ApplicationHelper

  test "capitalizes major words and keeps small words and acronyms" do
    assert_equal "New Document Type", title_case("New document type")
    assert_equal "Edit Correspondent", title_case("Edit correspondent")
    assert_equal "Merge Document Types?", title_case("Merge document types?")
    assert_equal "Pages of the Statement", title_case("pages of the statement")
    assert_equal "Add an AI Provider", title_case("Add an AI provider")
    assert_equal "Sign In", title_case("sign In")
  end
end
