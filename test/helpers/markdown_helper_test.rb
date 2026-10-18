require "test_helper"

class MarkdownHelperTest < ActionView::TestCase
  include MarkdownHelper, DocumentsHelper, MessagesHelper

  test "images become their alt text and are never loaded" do
    html = render_markdown("Logo: ![Acme Power logo](https://tracker.example.com/pixel.png) and ![](https://tracker.example.com/blank.png).")

    refute_includes html, "<img"
    refute_includes html, "tracker.example.com"
    assert_includes html, "Logo: Acme Power logo and ."
  end

  test "links stay clickable but pass nothing on" do
    html = render_markdown("See [the portal](https://portal.example.com/account).")

    assert_dom_equal %(<p>See <a href="https://portal.example.com/account" rel="noopener noreferrer nofollow">the portal</a>.</p>), html
  end

  test "raw HTML and script links are not rendered" do
    html = render_markdown(%(<img src="https://tracker.example.com/x.png"> <script>alert(1)</script> [click](javascript:alert(1))))

    refute_includes html, "<img"
    refute_includes html, "<script"
    refute_includes html, "javascript:"
  end

  test "OCR page text drops images and keeps tables" do
    document = Document.new(text_source: "docling")
    html = page_text(document, "| Item | Amount |\n| --- | --- |\n| Power | $87.40 |\n\n![Scanned signature](https://tracker.example.com/s.png)")

    assert_includes html, "<table>"
    assert_includes html, "Scanned signature"
    refute_includes html, "<img"
  end

  test "research answers drop images and keep citations" do
    cited = document_with_text("Bill", title: "March statement")
    message = Message.new(content: "Paid ![chart](https://tracker.example.com/c.png) [##{cited.id}] via [bank](https://bank.example.com).")

    html = render_answer(message)

    refute_includes html, "<img"
    assert_includes html, "chart"
    assert_includes html, %(rel="noopener noreferrer nofollow")
    assert_includes html, %(href="#{document_path(cited)}">[1]</a>)
  end
end
