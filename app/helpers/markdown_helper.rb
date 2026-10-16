module MarkdownHelper
  MARKDOWN_TAGS = %w[p br strong em del a ul ol li h1 h2 h3 h4 h5 h6 blockquote code pre table thead tbody tr th td hr].freeze
  MARKDOWN_ATTRIBUTES = %w[href rel class title data-turbo-frame].freeze
  LINK_REL = "noopener noreferrer nofollow".freeze

  # Markdown written by a model or OCR engine, as safe HTML. Raw HTML is
  # escaped by Commonmarker. Images become their alt text, because loading one
  # would tell its host that the page was opened; links stay clickable but
  # pass on nothing. A block can rewrite the HTML before it is sanitized.
  def render_markdown(text, hardbreaks: false, autolink: false)
    html = Commonmarker.to_html(text.to_s, options: { render: { unsafe: false, hardbreaks: hardbreaks }, extension: { table: true, strikethrough: true, autolink: autolink } })
    fragment = Nokogiri::HTML5.fragment(html)
    fragment.css("img").each do |image|
      alt = image["alt"].to_s.squish
      alt.present? ? image.replace(Nokogiri::XML::Text.new(alt, fragment.document)) : image.remove
    end
    fragment.css("a").each { |link| link["rel"] = LINK_REL }
    html = fragment.to_html
    html = yield(html) if block_given?

    sanitize(html, tags: MARKDOWN_TAGS, attributes: MARKDOWN_ATTRIBUTES)
  end
end
