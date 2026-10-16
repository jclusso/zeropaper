# Keyword and semantic indexes. Embeddings are always computed locally, so
# private documents are searchable the same way as everything else.
module Document::Searchable
  extend ActiveSupport::Concern

  CHUNK_SIZE = 1_200
  CHUNK_OVERLAP = 200
  # Documents this close by meaning are checked for shared text; documents
  # without text count as duplicates only when nearly identical in meaning.
  DUPLICATE_CANDIDATE_DISTANCE = 0.1
  DUPLICATE_CANDIDATES = 10
  DUPLICATE_DISTANCE = 0.02
  # ZeroPaper reads English only for now: stemming for search, eng for OCR.
  SEARCH_CONFIG = "english".freeze

  included do
    has_neighbors :embedding
  end

  def index!
    rebuild_chunks
    refresh_search_vector
    "#{chunks.count} #{"passage".pluralize(chunks.count)} embedded locally"
  end

  def refresh_search_vector
    language = self.class.connection.quote(Document::SEARCH_CONFIG)
    labels = [ correspondent&.name, document_type&.name, *tags.map(&:name) ].compact.join(" ")
    self.class.where(id: id).update_all([ <<~SQL, title.to_s, labels, summary.to_s, content.to_s.tr(Document::PAGE_BREAK, " ") ])
      search_vector =
        setweight(to_tsvector(#{language}::regconfig, ?), 'A') ||
        setweight(to_tsvector(#{language}::regconfig, ?), 'B') ||
        setweight(to_tsvector(#{language}::regconfig, ?), 'B') ||
        setweight(to_tsvector(#{language}::regconfig, left(?, 500000)), 'C')
    SQL
  end

  # A snippet around the first query term found in the text, read locally.
  def snippet_for(query, length: 220)
    text = content.to_s.tr(Document::PAGE_BREAK, " ").squish
    return summary.to_s.truncate(length) if text.blank?

    terms = query.to_s.scan(/[[:alnum:]]{3,}/)
    position = terms.filter_map { |term| text.downcase.index(term.downcase) }.min
    return text.truncate(length) unless position

    start = [ position - length / 3, 0 ].max
    excerpt = text[start, length]
    "#{"…" if start.positive?}#{excerpt}#{"…" if start + length < text.length}"
  end

  private
    def rebuild_chunks
      pieces = chunk_pieces
      vectors = Embedder.embed_documents(pieces.map { |piece| piece[:content] })
      language = self.class.connection.quote(Document::SEARCH_CONFIG)

      transaction do
        chunks.delete_all
        pieces.each_with_index do |piece, index|
          chunk = chunks.create!(position: index, page_number: piece[:page], content: piece[:content], embedding: vectors[index])
          Chunk.where(id: chunk.id).update_all([ "search_vector = to_tsvector(#{language}::regconfig, ?)", piece[:content] ])
        end
        update_columns(embedding: mean_vector(vectors))
      end
    end

    def chunk_pieces
      header = [ title, summary ].compact_blank.join("\n")
      pieces = page_texts.each_with_index.flat_map do |text, index|
        split_text(text).map { |piece| { page: pdf? ? index + 1 : nil, content: piece } }
      end
      pieces = [ { page: nil, content: header.presence || display_title } ] if pieces.empty?
      pieces
    end

    def split_text(text)
      text = text.to_s.strip
      return [] if text.blank?

      pieces = []
      start = 0
      while start < text.length
        finish = [ start + CHUNK_SIZE, text.length ].min
        if finish < text.length
          boundary = text.rindex(/\s/, finish)
          finish = boundary if boundary && boundary > start + CHUNK_SIZE / 2
        end
        pieces << text[start...finish].strip
        break if finish >= text.length

        start = finish - CHUNK_OVERLAP
      end
      pieces.compact_blank
    end

    def mean_vector(vectors)
      return if vectors.empty?

      sums = vectors.transpose.map(&:sum)
      norm = Math.sqrt(sums.sum { |value| value * value })
      norm.zero? ? sums : sums.map { |value| value / norm }
    end

    def flag_possible_duplicate
      return :skipped if embedding.nil?

      # Only the later of two copies is flagged, so reprocessing the original
      # does not point it back at its copy.
      nearest = Document.where.not(id: id).where.not(embedding: nil).where(created_at: ...created_at)
        .nearest_neighbors(:embedding, embedding, distance: "cosine").first(DUPLICATE_CANDIDATES)
        .find { |candidate| candidate.neighbor_distance < DUPLICATE_CANDIDATE_DISTANCE && duplicate_text?(candidate) }
      if nearest
        update_columns(duplicate_of_id: nearest.id)
        add_review_reason!("possible_duplicate")
        "Looks like “#{nearest.display_title}”"
      else
        update_columns(duplicate_of_id: nil)
        review_resolved!("possible_duplicate")
        "None found"
      end
    end

    def duplicate_text?(candidate)
      if content.blank? || candidate.content.blank?
        candidate.neighbor_distance < DUPLICATE_DISTANCE
      else
        TextOverlap.new(content, candidate.content).duplicate?
      end
    end
end
