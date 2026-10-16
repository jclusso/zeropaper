require "test_helper"

class DocumentPageTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "every view renders for each way text can be read" do
    document = ready_document
    [ "native", "tesseract", "tesseract + embedded text", "OpenAI · gpt-5.6-luna", nil ].each do |source|
      document.update_columns(text_source: source)

      get document_path(document)

      assert_response :success
      assert_select "[data-tabs-target=panel][data-name=activity]"
      assert_select "[data-tabs-target=panel][data-name=text]", count: 0
      assert_select "[data-reading-mode-target=reader]"
      assert_select "[data-reading-mode-mode-param=side]", text: "Side by side"
      assert_select "dd", text: document.text_source_label if source
    end
    assert_select "dd", text: "Tesseract (local) + embedded text", count: 0
  end

  test "AI text is shown as Markdown and engine text keeps its lines" do
    document = ready_document
    document.update_columns(content: "# Invoice\n\n| Item | Price |\n|---|---|\n| Oil | $89 |\f<script>alert(1)</script>", text_source: "OpenAI · gpt-5.6-luna")

    get document_path(document)

    assert_select "#text-page-1 .prose-answer table td", text: "$89"
    assert_select "#text-page-2 script", count: 0

    document.update_columns(text_source: "tesseract")
    get document_path(document)

    assert_select "#text-page-1 .whitespace-pre-wrap", text: /# Invoice/
    assert_select "#text-page-1 table", count: 0
  end

  test "everything to review sits in one bar" do
    duplicate = document_with_text("Original statement", title: "March statement")
    document = ready_document(page_count: 3, page_record: { "map" => [ 1, 2, 3 ], "blank" => [ 2 ] },
      duplicate_of_id: duplicate.id, metadata_source: "ai", confidence: 0.4)
    document.update_columns(needs_review: true, review_reasons: %w[blank_pages possible_duplicate low_confidence])

    get document_path(document)

    assert_select "section##{ActionView::RecordIdentifier.dom_id(document, :review)}", count: 1 do
      assert_select "span", text: "Needs review"
      assert_select "span", text: "· 3 items"
      assert_select "[data-review-item=blank_pages] button[commandfor=pages-dialog]", text: "Review pages"
      assert_select "[data-review-item=possible_duplicate] a[href=?]", document_comparison_path(document), text: "Compare"
      assert_select "[data-review-item=possible_duplicate] form[action=?]", document_duplicate_dismissal_path(document)
      assert_select "[data-review-item=details] button[data-tabs-name-param=details]", text: "Edit details"
      assert_select "[data-review-item=details] form[action=?] button", document_review_path(document), text: "Details are right"
      assert_select "button", text: /Mark all reviewed/, count: 0
    end
    assert_select "p.font-bold", text: "Needs review", count: 0
  end

  test "resolving an item updates the bar and marking all reviewed clears it" do
    duplicate = document_with_text("Original statement")
    document = ready_document(duplicate_of_id: duplicate.id)
    document.update_columns(needs_review: true, review_reasons: %w[possible_duplicate always])

    post document_duplicate_dismissal_path(document), headers: { "HTTP_REFERER" => document_url(document) }
    follow_redirect!
    assert_select "[data-review-item=possible_duplicate]", count: 0
    assert_select "[data-review-item=always]", count: 1

    post document_review_path(document), headers: { "HTTP_REFERER" => document_url(document) }
    follow_redirect!
    refute document.reload.needs_review?
    assert_select "section##{ActionView::RecordIdentifier.dom_id(document, :review)}", count: 0
  end

  test "checking a document leaves blank pages and duplicates to be fixed" do
    duplicate = document_with_text("Original statement")
    document = ready_document(page_count: 3, page_record: { "map" => [ 1, 2, 3 ], "blank" => [ 2 ] },
      duplicate_of_id: duplicate.id, metadata_source: "ai", confidence: 0.4)
    document.update_columns(needs_review: true, review_reasons: %w[blank_pages possible_duplicate low_confidence always])

    post document_review_path(document), headers: { "HTTP_REFERER" => document_url(document) }

    assert_equal %w[blank_pages possible_duplicate], document.reload.review_reasons
    assert document.needs_review?
  end

  test "a single item sits in the bar without a dropdown" do
    document = ready_document(page_count: 3, page_record: { "map" => [ 1, 2, 3 ], "blank" => [ 3 ] })
    document.update_columns(needs_review: true, review_reasons: %w[blank_pages])

    get document_path(document)

    assert_select "section##{ActionView::RecordIdentifier.dom_id(document, :review)}" do
      assert_select "[data-review-item=blank_pages]", text: /1 page looks blank \(3\)/, count: 1
      assert_select "[data-disclosure-target=button]", count: 0
    end
  end

  test "a reason with nothing left to fix can be cleared" do
    document = ready_document
    document.update_columns(needs_review: true, review_reasons: %w[possible_duplicate])

    get document_path(document)
    assert_select "[data-review-item=always] form[action=?]", document_review_path(document)

    post document_review_path(document)
    refute document.reload.needs_review?
  end

  test "saving details counts as checking them" do
    document = ready_document(metadata_source: "ai", confidence: 0.4)
    document.update_columns(needs_review: true, review_reasons: %w[low_confidence blank_pages], page_record: { "map" => [ 1, 2 ], "blank" => [ 2 ] })

    patch document_path(document), params: { document: { title: "Checked title" } }

    assert_equal %w[blank_pages], document.reload.review_reasons
  end

  test "turned pages appear as a note in the bar" do
    document = ready_document(page_count: 2, page_record: { "map" => [ 1, 2 ], "rotated" => { "2" => 180 } })

    get document_path(document)

    assert_select "span", text: "Note"
    assert_select "[data-review-item=rotated] p", text: "Page 2 was turned upright."
  end

  test "the privacy chip says where a document may be sent" do
    configure_openai
    document = ready_document

    get document_path(document)

    assert_select "el-dropdown button[aria-label=Privacy]", text: /Not private/
    assert_select "el-menu dd", text: "OpenAI · gpt-5.6-luna"
    assert_select "el-menu form[action=?] button", document_privacy_path(document), text: /Make private/
    assert_select "section", text: /May be sent to/, count: 0
  end

  test "a private document's chip gives its reason and no providers" do
    configure_openai
    document = ready_document(private: true, private_reason: "Added from the private folder")

    get document_path(document)

    assert_select "el-dropdown button[aria-label=Privacy]", text: /Private/
    assert_select "el-menu p", text: "Added from the private folder."
    assert_select "el-menu dd", count: 0
    assert_select "el-menu form[action=?] button", document_privacy_path(document), text: "Make not private"
  end

  test "a document being processed opens on a live Processing tab" do
    document = ready_document(status: "processing", steps: {
      "inspect" => { "status" => "done", "detail" => "2 pages" },
      "orientation" => { "status" => "done" },
      "blank_pages" => { "status" => "skipped" },
      "text" => { "status" => "running" }
    })

    get document_path(document)

    assert_select "[role=tab][aria-selected=true]", text: "Processing"
    assert_select "[data-tabs-target=panel][data-name=processing]:not([hidden])"
    assert_select "[data-tabs-target=panel][data-name=details][hidden]"
    assert_select "[data-step=text][data-status=running]"
    assert_select "[data-step=inspect][data-status=done] p", text: "2 pages"
    assert_select "[data-step=metadata][data-status=waiting] p", text: "Waiting"
    total = Document::Processing::STEPS.size
    assert_select "p", text: "Read text… step 4 of #{total}"
    assert_select "section##{ActionView::RecordIdentifier.dom_id(document, :review)}", count: 0
  end

  test "a queued document is waiting for a worker and finished ones have no Processing tab" do
    document = ready_document(status: "pending", steps: {})
    get document_path(document)
    assert_select "p", text: "Waiting for a worker"

    document.update_columns(status: "ready")
    get document_path(document)
    assert_select "[role=tab]", text: "Processing", count: 0
    assert_select "[role=tab][aria-selected=true]", text: "Details"
  end

  test "flash messages render as toasts" do
    document = ready_document

    post document_reprocessing_path(document)
    follow_redirect!

    assert_select "#toasts[data-turbo-permanent]"
    assert_select "[data-controller=toast][data-toast-delay-value='4000'][role=status] p", text: "Processing again."
  end

  test "deleting a document is a solid danger button" do
    get document_path(ready_document)

    assert_select "form[method=post] button.btn-danger-solid", text: /Delete/
  end

  private
    def ready_document(**attributes)
      document = ingest(text_pdf("One", "Two", "Three"), filename: "statement.pdf")
      document.update_columns({ status: "ready", page_count: 1, title: "Statement", steps: {} }.merge(attributes))
      document.reload
    end
end
