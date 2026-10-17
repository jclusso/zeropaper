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
    assert_select "tr[data-comparison-row=Source]", count: 0
    assert_select "tr[data-comparison-row=Added]", count: 0
    assert_select "[data-comparison-column=#{@copy.id}] [data-comparison-added]", text: "Added #{@copy.created_at.to_fs(:long)} · Upload"
  end

  test "shows how similar the text is" do
    get document_comparison_path(@copy)

    assert_select "[data-comparison-score]", text: "100%"
    assert_select "[data-comparison-verdict]", text: "Very likely the same document"
    assert_select "[data-comparison-confidence=high] [data-comparison-guidance]", text: /delete the other/
    assert_select "[data-comparison-basis]", text: "From shared wording"
    assert_select "[data-comparison-measure=wording][data-decides=true]", text: /Runs of three words in both/
    assert_select "#comparison_score_tip", text: /Runs of three words/
    assert_select "tr[data-comparison-row=Date][data-same=true]"
  end

  test "uses the local embeddings when a document has no text" do
    [ @original, @copy ].each(&:index!)
    @original.update_columns(content: nil)

    get document_comparison_path(@copy)

    assert_select "[data-comparison-basis]", text: "From meaning"
    assert_select "[data-comparison-measure=meaning][data-decides=true]"
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

  test "a copy with a page removed lines up with the full scan around the gap" do
    front, middle, back = [ PdfFactory.printed, PdfFactory.blank.rect(40, 40, 320, 120, 0), PdfFactory.blank.rect(40, 330, 320, 150, 0) ]
    full = ingest(scanned_pdf(front, middle, back), filename: "full.pdf")
    trimmed = ingest(scanned_pdf(front, back), filename: "trimmed.pdf")
    full.update_columns(page_count: 3)
    trimmed.update_columns(page_count: 2)

    get document_comparison_path(trimmed, other: full.id)

    assert_select "tr[data-comparison-row=Pages][data-same=false] [data-comparison-note]", text: "1 page only in the other"
    assert_select "[data-comparison-score]", text: "67%"
    assert_select "[data-comparison-measure=pages]", text: /2 of 3 pages with content/
    assert_select "[data-comparison-column=#{trimmed.id}] ol > li" do |cells|
      assert_equal [ false, true, false ], cells.map { it.key?("data-comparison-gap") }
    end
    assert_select "[data-comparison-column=#{full.id}] [data-comparison-gap]", count: 0
    assert_equal [ { trimmed.id.to_s => 1, full.id.to_s => 1 }, { full.id.to_s => 2 }, { trimmed.id.to_s => 2, full.id.to_s => 3 } ], viewer_pages(trimmed, full)
  end

  test "pages removed from a copy are shown from its upload, lined up with the full scan" do
    front, middle, back = [ PdfFactory.printed, PdfFactory.blank.rect(40, 40, 320, 120, 0), PdfFactory.blank.rect(40, 330, 320, 150, 0) ]
    full = ingest(scanned_pdf(front, middle, back), filename: "full.pdf")
    copy = ingest(scanned_pdf(front, PdfFactory.blank.rect(40, 40, 320, 120, 0).rect(5, 5, 2, 2, 0), back), filename: "copy.pdf")
    full.update_columns(page_count: 3)
    copy.update!(page_count: 3, status: "ready")
    copy.remove_pages!([ 2 ])
    copy.update!(status: "ready")

    get document_comparison_path(copy, other: full.id)

    assert_select "tr[data-comparison-row=Pages][data-same=true] [data-comparison-note]", text: "Same apart from blank pages"
    assert_select "tr[data-comparison-row=Pages] td", text: "2 · 1 removed"
    assert_select "[data-comparison-score]", text: "100%"
    assert_select "[data-comparison-basis]", text: "From matching pages"
    assert_select "[data-comparison-measure]", count: 1
    assert_select "[data-comparison-measure=pages][data-decides=true] [role=meter][aria-valuenow='100']"

    # Read separately, the columns came out in another order.
    copy.update!(content: "Invoice 461759 for the X5\n\nVIN 5YMJU0C0N9K62003 total 1234.56")
    full.update!(content: "VIN 5YMJU0C0N9K62003 total 1234.56\n\nInvoice 461759 for the X5")
    get document_comparison_path(copy, other: full.id)
    assert_select "[data-comparison-score]", text: "100%"
    assert_select "[data-comparison-basis]", text: "Lower of matching pages and shared numbers"
    assert_select "[data-comparison-measure=numbers]", text: /3 of 3 numbers in both/
    assert_select "[data-comparison-measure=wording]", count: 0
    assert_select "#comparison_score_tip", text: /Wording is not counted/
    assert_select "[data-comparison-confidence=high]"
    assert_select "#comparison_numbers_tip", text: /invoice and account numbers/

    # Pages alike by look but other numbers, as two fills of one form can be.
    full.update!(content: "VIN 5YMJU0C0N9K99999 total 9876.54\n\nInvoice 470001 for the X5")
    get document_comparison_path(copy, other: full.id)
    assert_select "[data-comparison-score]", text: "0%"
    assert_select "[data-comparison-verdict]", text: "Probably different documents"
    assert_select "[data-comparison-confidence=low]"
    assert_select "[data-comparison-measure=numbers][data-decides=true]", text: /0%/
    assert_select "[data-comparison-measure=pages][data-decides=false]", text: /100%/
    assert_select "[data-comparison-column=#{copy.id}] ol > li", count: 3
    assert_select "[data-comparison-column=#{copy.id}] li[data-comparison-removed='2'] img[src=?]",
      document_page_path(copy, 2, size: "thumb", source: "original", v: copy.original_file.blob.id)
    assert_select "[data-comparison-gap]", count: 0
    assert_equal [ { copy.id.to_s => 1, full.id.to_s => 1 }, { full.id.to_s => 2 }, { copy.id.to_s => 2, full.id.to_s => 3 } ], viewer_pages(copy, full)

    get document_page_path(copy, 2, size: "thumb", source: "original")
    assert_response :success
    get document_page_path(copy, 4, size: "thumb", source: "original")
    assert_response :not_found
  end

  test "page counts leave out blank pages, so a copy with its blank backs removed counts the same" do
    front, back = PdfFactory.printed, PdfFactory.blank.rect(40, 330, 320, 150, 0)
    full = ingest(scanned_pdf(front, PdfFactory.blank, back), filename: "full.pdf")
    trimmed = ingest(scanned_pdf(front, back), filename: "trimmed.pdf")
    full.update_columns(page_count: 3, page_record: { "map" => [ 1, 2, 3 ], "blank" => [ 2 ] })
    trimmed.update_columns(page_count: 2)

    get document_comparison_path(trimmed, other: full.id)

    assert_select "tr[data-comparison-row=Pages] [data-comparison-note]", text: "Same apart from blank pages"
    assert_select "tr[data-comparison-row=Pages][data-same=true]" do
      assert_select "td", text: "2"
      assert_select "td", text: "3 · 1 looks blank"
    end
    assert_select "[data-comparison-column=#{full.id}] [data-comparison-blank]", count: 1
  end

  test "the side by side preview hides blank pages the other does not have, so the pages line up" do
    front, back = PdfFactory.printed, PdfFactory.blank.rect(40, 330, 320, 150, 0)
    full = ingest(scanned_pdf(front, PdfFactory.blank, back), filename: "full.pdf")
    trimmed = ingest(scanned_pdf(front, back), filename: "trimmed.pdf")
    full.update!(page_count: 3, status: "ready", page_record: { "map" => [ 1, 2, 3 ], "blank" => [ 2 ] })
    trimmed.update!(page_count: 2, status: "ready")

    assert_equal [ { trimmed.id.to_s => 1, full.id.to_s => 1 }, { trimmed.id.to_s => 2, full.id.to_s => 2 } ], viewer_pages(trimmed, full)
    url = document_file_path(full, variant: "viewable", v: full.file.blob.id, pages: "1,3")
    assert_select "[data-comparison-viewer=#{full.id}] [data-pdf-viewer-url-value=?] [data-pdf-viewer-target=pageCount]", url, text: "2"
    assert_select "[data-comparison-viewer=#{trimmed.id}] [data-pdf-viewer-url-value=?]", document_file_path(trimmed, variant: "viewable", v: trimmed.file.blob.id)

    get url
    assert_response :success
    assert_equal "application/pdf", response.media_type
    with_pdf_file(response.body) { |path| assert_equal 2, Pdf.page_count(path) }
    get document_file_path(full, variant: "viewable", pages: "1,4")
    assert_response :not_found

    assert_equal [ { trimmed.id.to_s => 1, full.id.to_s => 1 }, { full.id.to_s => 2 }, { trimmed.id.to_s => 2, full.id.to_s => 3 } ], viewer_pages(trimmed, full, blank: "show")
    assert_select "[data-comparison-viewer=#{full.id}] [data-pdf-viewer-url-value=?]", document_file_path(full, variant: "viewable", v: full.file.blob.id)

    get document_comparison_path(trimmed, other: full.id)
    assert_select "#comparison-dialog button[data-pdf-compare-target=blank][aria-pressed=false]", text: /Blank pages/
    assert_select "#comparison-dialog turbo-frame[data-pdf-compare-target=frame]"
  end

  test "showing blank pages shows a copy's whole upload, so removed pages line up with the full scan" do
    front, back = PdfFactory.printed, PdfFactory.blank.rect(40, 330, 320, 150, 0)
    full = ingest(scanned_pdf(front, PdfFactory.blank, back), filename: "full.pdf")
    copy = ingest(scanned_pdf(front, PdfFactory.blank.rect(5, 5, 2, 2, 0), back), filename: "copy.pdf")
    full.update!(page_count: 3, status: "ready", page_record: { "map" => [ 1, 2, 3 ], "blank" => [ 2 ] })
    copy.update!(page_count: 3, status: "ready", page_record: { "map" => [ 1, 2, 3 ], "blank" => [ 2 ] })
    copy.remove_pages!([ 2 ])
    copy.update!(status: "ready")

    assert_equal [ { copy.id.to_s => 1, full.id.to_s => 1 }, { copy.id.to_s => 2, full.id.to_s => 2 } ], viewer_pages(copy, full)

    assert_equal [ { copy.id.to_s => 1, full.id.to_s => 1 }, { copy.id.to_s => 2, full.id.to_s => 2 }, { copy.id.to_s => 3, full.id.to_s => 3 } ], viewer_pages(copy, full, blank: "show")
    assert_select "[data-comparison-viewer=#{copy.id}] [data-pdf-viewer-url-value=?]", document_file_path(copy, variant: "original", v: copy.original_file.blob.id) do
      assert_select "[data-pdf-viewer-target=pageCount]", text: "3"
      assert_select "[data-pdf-viewer-target=thumb]", text: /2 · removed/
    end
  end

  test "the same file, or the same upload before pages were removed, is named as such" do
    upload = text_pdf("Page one has words", "Page two has words")
    edited = ingest(upload, filename: "edited.pdf")
    edited.update!(page_count: 2, status: "ready")
    upload_checksum = edited.checksum
    edited.remove_pages!([ 2 ])
    edited.update!(status: "ready")
    other = document_with_text("Page one has words", title: "Full upload")
    other.update_columns(checksum: upload_checksum)

    get document_comparison_path(edited, other: other.id)
    assert_select "tr[data-comparison-row=Checksum][data-same=true]" do
      assert_select "td", text: upload_checksum.first(12), count: 2
    end
    assert_select "[data-comparison-verdict]", text: "The same upload"
    assert_select "[data-comparison-verdict]", text: "The same file", count: 0

    other.update_columns(checksum: edited.reload.checksum)
    get document_comparison_path(edited, other: other.id)
    assert_select "[data-comparison-verdict]", text: "The same file"

    get document_comparison_path(@copy, other: @original.id)
    assert_select "tr[data-comparison-row=Checksum][data-same=false] [data-comparison-note]", text: /as uploaded/
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

  private
    # The page pairing the side by side viewers link scrolling by.
    def viewer_pages(document, other, **params)
      get document_comparison_path(document, other: other.id, **params), headers: { "Turbo-Frame" => dom_id(document, :comparison_viewers) }
      JSON.parse(css_select("[data-pdf-compare-target=pages]").first["data-pages"])
    end
end
