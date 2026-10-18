module MessagesHelper
  CITATION = /\[#(\d+)\]/
  REPEATED_CITATION = /(\[#(\d+)\])(?:\s*\[#\2\])+/
  # A tag is matched whole so markers in attributes, such as a heading
  # anchor's label, stay text. The space before a marker is taken with it.
  TAG_OR_CITATION = /<[^>]*>|\s*\[#(\d+)\]/
  # Keeps a marker on the line of the word it follows.
  WORD_JOINER = "⁠".freeze
  READING = /\AReading document #(\d+)\z/

  # Renders an answer's Markdown and turns [#123] markers into numbered
  # links to the cited documents, set against the word before them. A
  # document cited twice in a row is linked once.
  def render_answer(message)
    render_markdown(message.content, autolink: true) do |html|
      sources = answer_sources(message)
      html.gsub(REPEATED_CITATION, '\1').gsub(TAG_OR_CITATION) do |match|
        next match unless (id = Regexp.last_match(1)&.to_i)

        if (index = sources.index { it.id == id })
          WORD_JOINER + link_to("[#{index + 1}]", document_path(id), class: "citation-marker", data: { turbo_frame: "_top" })
        else
          ""
        end
      end
    end
  end

  # The documents an answer cites that may be shown, numbered from 1 in
  # this order. A finished answer uses its recorded citations, as its
  # Sources list does; one still streaming, with none recorded yet, takes
  # them in the order they appear.
  def answer_sources(message)
    (@answer_sources ||= {})[message] ||=
      message.cited_document_ids.any? ? message.cited_documents : cited_in(message.content)
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

  private
    def cited_in(content)
      ids = content.to_s.scan(CITATION).flatten.map(&:to_i).uniq
      documents = Document.shareable.where(id: ids).index_by(&:id)
      ids.filter_map { documents[it] }
    end
end
