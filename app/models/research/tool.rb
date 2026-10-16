class Research::Tool < RubyLLM::Tool
  def initialize(research)
    super()
    @research = research
  end

  private
    attr_reader :research

    def describe(document, query: nil)
      {
        id: document.id,
        title: document.display_title,
        date: document.document_date&.iso8601,
        correspondent: document.correspondent&.name,
        document_type: document.document_type&.name,
        tags: document.tags.map(&:name),
        summary: document.summary,
        excerpt: (document.snippet_for(query, length: 400) if query)
      }.compact
    end

    def filters(date_from: nil, date_to: nil, correspondent: nil, document_type: nil, tag: nil)
      {
        date_from: date_from,
        date_to: date_to,
        correspondent_id: (Correspondent.named(correspondent)&.id || -1 if correspondent.present?),
        document_type_ids: ([ DocumentType.named(document_type)&.id || -1 ] if document_type.present?),
        tag_ids: ([ Tag.named(tag)&.id || -1 ] if tag.present?)
      }.compact
    end
end
