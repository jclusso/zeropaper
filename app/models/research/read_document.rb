class Research::ReadDocument < Research::Tool
  MAX_CHARACTERS = 30_000

  description "Reads a document's full text by id, page by page."
  parameter :id, type: "integer", description: "Document id from a search result"

  def execute(id:)
    document = Document.ready.find_by(id: id)
    return { error: "No document with id #{id} is available." } if document.nil? || document.private?

    research.shareable([ document ])
    pages = document.page_texts.each_with_index.filter_map { |text, index| "[page #{index + 1}]\n#{text.strip}" if text.present? }
    text = pages.join("\n\n")

    describe(document).merge(
      text: text.first(MAX_CHARACTERS),
      truncated: text.length > MAX_CHARACTERS
    )
  end
end
