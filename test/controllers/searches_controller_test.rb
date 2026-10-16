require "test_helper"

class SearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @bill = document_with_text(BILL_TEXT, title: "Electricity statement", document_date: Date.new(2026, 3, 14),
      correspondent: correspondents(:acme_power), document_type: document_types(:invoice))
    @letter = document_with_text("Letter about the electricity meter", title: "Meter letter", document_date: Date.new(2025, 6, 1))
    [ @bill, @letter ].each(&:index!)
  end

  test "names and dates in the query fill in the filters" do
    get search_path(q: "electricity from Acme Power 2026")

    assert_redirected_to search_path(q: "electricity", correspondent_id: correspondents(:acme_power).id, date_from: "2026-01-01", date_to: "2026-12-31")
    follow_redirect!

    assert_select "input[type=hidden][name=correspondent_id][value=?]", correspondents(:acme_power).id.to_s
    assert_select "input[name=date_from][value='2026-01-01']"
    assert_select "input[name=q][value=electricity]"
    assert_select "p", text: /“from Acme Power” is set as a filter/
    assert_select "a[href='#{document_path(@bill)}']"
    assert_select "a[href='#{document_path(@letter)}']", count: 0
  end

  test "a query that is only filters lists the matching documents" do
    get search_path(q: "march 2026")
    follow_redirect!

    assert_select "input[name=date_from][value='2026-03-01']"
    assert_select "a[href='#{document_path(@bill)}']"
    assert_select "a[href='#{document_path(@letter)}']", count: 0
  end

  test "a filter picked in the bar wins over the query" do
    get search_path(q: "electricity 2025", date_from: "2026-01-01")

    assert_response :success
    assert_select "a[href='#{document_path(@bill)}']"
  end

  test "searching a phrase as words keeps it out of the filters" do
    get search_path(q: "electricity from Acme Power", literal: [ "from Acme Power" ])

    assert_response :success
    assert_select "input[name='literal[]'][value='from Acme Power']"
    assert_select "a[href='#{document_path(@bill)}']"
  end

  test "there is no AI search option" do
    get search_path(q: "electricity")

    assert_no_match(/Smart search/i, response.body)
    assert_select "input[name=ai]", count: 0
  end
end
