class Research::SearchDocuments < Research::Tool
  description "Searches the archive by keywords and meaning. Returns matching documents with their details and an excerpt."
  parameter :query, description: "What to look for"
  parameter :date_from, description: "Only documents dated on or after this day, YYYY-MM-DD", required: false
  parameter :date_to, description: "Only documents dated on or before this day, YYYY-MM-DD", required: false
  parameter :correspondent, description: "Exact correspondent name", required: false
  parameter :document_type, description: "Exact document type name", required: false
  parameter :tag, description: "Exact tag name", required: false
  parameter :limit, type: "integer", description: "Maximum results, default 10, at most 25", required: false

  def execute(query:, date_from: nil, date_to: nil, correspondent: nil, document_type: nil, tag: nil, limit: 10)
    found = Search.new(query: query, filters: filters(date_from:, date_to:, correspondent:, document_type:, tag:), scope: Document.ready)
      .results(limit: limit.to_i.clamp(1, 25))
    documents = research.shareable(found)

    { results: documents.map { |document| describe(document, query: query) } }
  end
end
