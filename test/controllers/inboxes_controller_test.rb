require "test_helper"

class InboxesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "a possible duplicate links to the comparison" do
    original = document_with_text("Electricity statement", title: "March statement")
    copy = document_with_text("Electricity statement", title: "March statement copy", duplicate_of: original,
      needs_review: true, review_reasons: [ "possible_duplicate" ])

    get inbox_path

    assert_response :success
    assert_select "a[href='#{document_comparison_path(copy)}']", text: "Compare"
    assert_select "a[href='#{document_path(original)}']", text: "Compare", count: 0
    assert_select "form[action='#{document_review_path(copy)}']", count: 0
  end

  test "looks good appears only when nothing else needs fixing" do
    document_with_text("Water bill", needs_review: true, review_reasons: %w[always low_confidence])

    get inbox_path

    assert_select "form[action$='/review'] button", text: /Looks good/, count: 1
  end

  test "a processing error shows in the failed badge's tooltip, not as a line" do
    document_with_text("Lease payoff", status: "failed", error: "Processing stopped unexpectedly.",
      needs_review: true, review_reasons: [ "failed" ])

    get inbox_path

    assert_select "[role=tooltip]", text: "Processing stopped unexpectedly."
    assert_select "p.text-danger", count: 0
  end
end
