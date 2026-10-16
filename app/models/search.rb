# Hybrid search: Postgres full-text and title similarity for keywords, local
# embeddings for meaning, merged with reciprocal rank fusion. Runs entirely
# on this machine, so private documents are found like any other.
class Search
  RRF_K = 60
  KEYWORD_CANDIDATES = 100
  SEMANTIC_CANDIDATES = 20

  attr_reader :query

  def initialize(query:, filters: {}, scope: Document.all)
    @query = query.to_s.squish
    @scope = scope.filter_by(filters)
  end

  def results(limit: 50)
    return @scope.chronologically.limit(limit).to_a if query.blank?

    ids = ranked_ids.first(limit)
    documents = @scope.where(id: ids).includes(:correspondent, :document_type, :tags).index_by(&:id)
    ids.filter_map { |id| documents[id] }
  end

  def ranked_ids
    scores = Hash.new(0.0)
    [ keyword_ids, semantic_ids ].each do |ids|
      ids.each_with_index { |id, rank| scores[id] += 1.0 / (RRF_K + rank + 1) }
    end
    scores.sort_by { |id, score| [ -score, -id ] }.map(&:first)
  end

  private
    def keyword_ids
      language = Document.connection.quote(Document::SEARCH_CONFIG)
      tsquery = "websearch_to_tsquery(#{language}::regconfig, #{Document.connection.quote(query)})"
      quoted_query = Document.connection.quote(query)

      @scope
        .where("documents.search_vector @@ #{tsquery} OR word_similarity(#{quoted_query}, coalesce(documents.title, '')) > 0.5")
        .order(Arel.sql("ts_rank_cd(documents.search_vector, #{tsquery}) + word_similarity(#{quoted_query}, coalesce(documents.title, '')) DESC"))
        .limit(KEYWORD_CANDIDATES)
        .pluck(:id)
    end

    def semantic_ids
      vector = Embedder.embed_query(query)
      Chunk.where(document_id: @scope.select(:id))
        .nearest_neighbors(:embedding, vector, distance: "cosine")
        .limit(SEMANTIC_CANDIDATES * 4)
        .pluck(:document_id)
        .uniq
        .first(SEMANTIC_CANDIDATES)
    rescue StandardError => error
      Rails.logger.warn("[search] semantic search unavailable: #{error.message}")
      []
    end
end
