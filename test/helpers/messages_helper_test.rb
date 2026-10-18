require "test_helper"

class MessagesHelperTest < ActionView::TestCase
  include MarkdownHelper, DocumentsHelper, MessagesHelper

  test "citations are numbered in the order the answer first cites them" do
    invoice = document_with_text("Oil change", title: "Service invoice")
    inspection = document_with_text("Passed", title: "Inspection")
    message = Message.new(content: "Serviced [##{inspection.id}] and inspected [##{invoice.id}], then serviced again [##{inspection.id}].")

    html = render_answer(message)

    assert_equal [ "[1]", "[2]", "[1]" ], html.scan(/>(\[\d\])</).flatten
    assert_includes html, %(href="#{document_path(inspection)}">[1]</a>)
    assert_includes html, "Serviced⁠<a", "a marker stays on the line of the word before it"
  end

  test "a finished answer numbers citations as its sources list does and links a repeat once" do
    first = document_with_text("One", title: "First")
    second = document_with_text("Two", title: "Second")
    message = Message.new(cited_document_ids: [ second.id, first.id ],
      content: "Both [##{first.id}][##{first.id}] and [##{second.id}].")

    html = render_answer(message)

    assert_equal [ second, first ], message.cited_documents
    assert_equal [ "[2]", "[1]" ], html.scan(/>(\[\d\])</).flatten
  end

  test "a citation in a heading links in the text and leaves the heading anchor whole" do
    cited = document_with_text("Seal", title: "Marriage certificate")
    message = Message.new(content: "## Bears the raised seal [##{cited.id}].\n\nDone.")

    html = render_answer(message)

    assert_equal 1, html.scan("citation-marker").size
    assert_match %r{<h2[^>]*>Bears the raised seal⁠<a class="citation-marker"[^>]*>\[1\]</a>\.}, html
    refute_includes html, "&lt;a"
  end

  test "citations of documents that may not be shown are dropped without using a number" do
    secret = document_with_text("Private", private: true)
    shown = document_with_text("Shown", title: "Shown")
    message = Message.new(content: "Hidden [##{secret.id}] and shown [##{shown.id}].")

    html = render_answer(message)

    assert_equal [ "[1]" ], html.scan(/>(\[\d\])</).flatten
    refute_includes html, "##{secret.id}"
  end
end
