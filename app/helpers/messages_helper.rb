module MessagesHelper
  CITATION = /\[#(\d+)\]/
  READING = /\AReading document #(\d+)\z/

  # Renders an answer's Markdown and turns [#123] markers into links to the
  # cited documents.
  def render_answer(message)
    render_markdown(message.content, autolink: true) do |html|
      titles = Document.shareable.where(id: html.scan(CITATION).flatten.map(&:to_i)).pluck(:id, :title).to_h
      html.gsub(CITATION) do
        id = Regexp.last_match(1).to_i
        if titles.key?(id)
          link_to(titles[id].presence || "Document #{id}", document_path(id), class: "citation inline-block max-w-56 truncate align-bottom", title: "Open document", data: { turbo_frame: "_top" })
        else
          ""
        end
      end
    end
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
