require "test_helper"

class DatePickerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "library date filters use the picker and carry YYYY-MM-DD under the filter names" do
    get documents_path(date_from: "2026-03-01")

    assert_response :success
    assert_select "input[type=date]", count: 0
    assert_select "[data-controller=date-picker] input[type=hidden][name=date_from][value='2026-03-01'][data-action~='change->auto-submit#submit']"
    assert_select "input#filter_date_from[type=text][value='Mar 1, 2026']"
    assert_select "[data-controller=date-picker] input[type=hidden][name=date_to]:not([value])"
    assert_select "input#filter_date_to[placeholder='Any date']"
  end

  test "document details date uses the picker and saves through the hidden field" do
    document = document_with_text("Lease payoff", document_date: Date.new(2025, 6, 30))

    get document_path(document)
    assert_select "input[type=date]", count: 0
    assert_select "input[type=hidden][name='document[document_date]'][value='2025-06-30']"
    assert_select "input#document_document_date[value='Jun 30, 2025']"
    assert_select "template[data-date-picker-target=dayTemplate] button.date-picker-day"
    assert_select "[data-date-picker-target=panel][popover=manual] [role=grid]"

    patch document_path(document), params: { document: { document_date: "2026-03-26" } }
    assert_equal Date.new(2026, 3, 26), document.reload.document_date

    patch document_path(document), params: { document: { document_date: "" } }
    assert_nil document.reload.document_date
  end
end
