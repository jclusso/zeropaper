module MessagesHelper
  CITATION = /\[#(\d+)\]/
  READING = /\AReading document #(\d+)\z/

  # Renders an answer's Markdown and turns [#123] markers into links to the
  # cited documents. Raw HTML in the answer is escaped by Commonmarker.
  def render_answer(message)
    html = Commonmarker.to_html(message.content.to_s, options: { render: { unsafe: false }, extension: { table: true, strikethrough: true, autolink: true } })
    titles = Document.shareable.where(id: html.scan(CITATION).flatten.map(&:to_i)).pluck(:id, :title).to_h
    html = html.gsub(CITATION) do
      id = Regexp.last_match(1).to_i
      if titles.key?(id)
        link_to(titles[id].presence || "Document #{id}", document_path(id), class: "citation inline-block max-w-56 truncate align-bottom", title: "Open document", data: { turbo_frame: "_top" })
      else
        ""
      end
    end
    sanitize(html, tags: %w[p br strong em del a ul ol li h1 h2 h3 h4 blockquote code pre table thead tbody tr th td hr], attributes: %w[href class title data-turbo-frame])
  end

  # Step labels with "Reading document #12" turned into the document's title,
  # for documents that may be shown.
  def research_step_labels(message)
    labels = message.steps.map { |step| step["label"].to_s }
    ids = labels.filter_map { |label| label[READING, 1]&.to_i }
    titles = ids.any? ? Document.shareable.where(id: ids).to_h { |document| [ document.id, document.display_title ] } : {}

    labels.map do |label|
      id = label[READING, 1]&.to_i
      id && titles[id] ? "Reading “#{titles[id]}”" : label
    end
  end
end
