require "test_helper"

class Documents::ComparisonsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @original = document_with_text(BILL_TEXT, title: "Acme statement", document_date: Date.new(2026, 3, 14), correspondent: correspondents(:acme_power))
    @copy = document_with_text(BILL_TEXT, title: "Acme statement copy", document_date: Date.new(2026, 3, 14), correspondent: correspondents(:acme_power),
      duplicate_of: @original, needs_review: true, review_reasons: %w[possible_duplicate])
  end

  test "shows both documents side by side with differing rows highlighted" do
    get document_comparison_path(@copy)

    assert_response :success
    assert_select "h1", text: "Compare Documents"
    assert_select "[data-comparison-column=#{@copy.id}]" do
      assert_select "p", text: "This document"
      assert_select "a[href=?]", document_path(@copy), text: "Acme statement copy"
    end
    assert_select "[data-comparison-column=#{@original.id}] p", text: "Possible original"
    assert_select "tr[data-comparison-row=Title][data-same=false]"
    assert_select "tr[data-comparison-row=Date][data-same=true]"
    assert_select "tr[data-comparison-row=Correspondent][data-same=true]"
  end

  test "shows how similar the text is" do
    get document_comparison_path(@copy)

    assert_select "#comparison-summary p", text: "100%"
    assert_select "#comparison-summary p", text: "similar by shared text"
    assert_select "[data-comparison-fact]", text: "Same date"
  end

  test "uses the local embeddings when a document has no text" do
    [ @original, @copy ].each(&:index!)
    @original.update_columns(content: nil)

    get document_comparison_path(@copy)

    assert_select "#comparison-summary p", text: "similar by meaning"
  end

  test "each column keeps itself and deletes the other, naming both" do
    get document_comparison_path(@copy)

    assert_select "[data-comparison-column='#{@copy.id}'] form[action=?]", document_path(@original) do |forms|
      assert_match "Keep “#{@copy.display_title}”", forms.first["data-turbo-confirm"]
      assert_match "delete “#{@original.display_title}”", forms.first["data-turbo-confirm"]
      assert_select "button", text: /Keep this one/
    end
    assert_select "[data-comparison-column='#{@original.id}'] form[action=?] button", document_path(@copy), text: /Keep this one/
    assert_select "#comparison-actions form[action=?][data-turbo-confirm-button='Keep both'] button", document_duplicate_dismissal_path(@copy), text: "Not duplicates, keep both"
    assert_select "a", text: "Keep both", count: 0
  end

  test "deleting this one opens the other" do
    delete document_path(@copy), params: { then_open: @original.id }

    assert_redirected_to document_path(@original)
    refute Document.exists?(@copy.id)
  end

  test "deleting the other one clears this one's duplicate flag" do
    delete document_path(@original), params: { then_open: @copy.id }

    assert_redirected_to document_path(@copy)
    @copy.reload
    assert_nil @copy.duplicate_of
    refute_includes @copy.review_reasons, "possible_duplicate"
  end

  test "clicking a page opens both documents side by side in a dialog" do
    pdf = ingest(text_pdf("One", "Two"), filename: "statement.pdf")
    process(pdf)

    get document_comparison_path(@copy, other: pdf.id)

    assert_select "[data-comparison-column=#{pdf.id}] button[command=show-modal][commandfor=comparison-dialog]", count: 2
    assert_select "dialog#comparison-dialog turbo-frame[id=?][loading=lazy][src=?]", dom_id(@copy, :comparison_viewers), document_comparison_path(@copy, other: pdf.id)
    assert_select "[data-pdf-compare-target=link]", count: 0
  end

  test "two PDFs can be paged and zoomed together" do
    first, second = [ "One", "Two" ].map { |text| process(ingest(text_pdf(text), filename: "#{text}.pdf")) }

    get document_comparison_path(first, other: second.id)

    assert_select "#comparison-dialog [data-controller=pdf-compare] button[data-pdf-compare-target=link][aria-pressed=true]", text: /Move together/
    assert_select "#comparison-dialog kbd", text: "j"
  end

  test "the dialog's frame loads each document's viewer" do
    pdf = ingest(text_pdf("One", "Two"), filename: "statement.pdf")
    process(pdf)

    get document_comparison_path(@copy, other: pdf.id), headers: { "Turbo-Frame" => dom_id(@copy, :comparison_viewers) }

    assert_response :success
    assert_select "turbo-frame[id=?]", dom_id(@copy, :comparison_viewers) do
      assert_select "[data-comparison-viewer=#{@copy.id}]", text: /This document/
      assert_select "[data-comparison-viewer=#{pdf.id}] [data-controller=pdf-viewer]"
      assert_select "[data-comparison-viewer=#{pdf.id}] a[href=?][data-turbo-frame=_top]", document_path(pdf)
    end
    assert_select "#comparison-summary", count: 0
  end

  test "any two documents can be compared" do
    other = document_with_text("Something else entirely", title: "Dentist letter")

    get document_comparison_path(@original, other: other.id)

    assert_response :success
    assert_select "[data-comparison-column=#{other.id}] p", text: "Other document"
    assert_select "form[action=?]", document_duplicate_dismissal_path(@original), count: 0
  end

  test "a document that is not a duplicate goes back to itself" do
    get document_comparison_path(@original)

    assert_redirected_to document_path(@original)
    assert_equal "This document is not flagged as a duplicate.", flash[:notice]
  end

  test "the review bar's Compare opens the comparison" do
    get document_path(@copy)

    assert_select "[data-review-item=possible_duplicate] a[href=?]", document_comparison_path(@copy), text: "Compare"
  end
end
