# Hybrid search: Postgres full-text and title similarity for keywords, local
# embeddings for meaning, merged with reciprocal rank fusion. Runs entirely
# on this machine, so private documents are found like any other.
class Search
  RRF_K = 60
  KEYWORD_CANDIDATES = 100
  SEMANTIC_CANDIDATES = 20
  # Nearest passages fetched per round, and how many rounds a search may
  # take before it settles for fewer documents.
  SEMANTIC_BATCH = 80
  SEMANTIC_ROUNDS = 5
  TITLE_SIMILARITY = 0.5

  attr_reader :query

  # pgvector 0.8 can keep scanning the HNSW index until enough rows pass
  # the filter; before that a scan stops at ef_search (40) rows.
  def self.iterative_scan?
    return @iterative_scan if defined?(@iterative_scan)

    version = Chunk.connection.select_value("SELECT extversion FROM pg_extension WHERE extname = 'vector'")
    @iterative_scan = Gem::Version.new(version.to_s) >= Gem::Version.new("0.8.0")
  end

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

      # <% is word_similarity above the threshold, written as an operator so
      # the title's trigram index and the full-text index can both be used.
      Document.transaction do
        Document.connection.execute("SET LOCAL pg_trgm.word_similarity_threshold = #{TITLE_SIMILARITY}")
        @scope
          .where("documents.search_vector @@ #{tsquery} OR #{quoted_query} <% documents.title")
          .order(Arel.sql("ts_rank_cd(documents.search_vector, #{tsquery}) + word_similarity(#{quoted_query}, coalesce(documents.title, '')) DESC"))
          .limit(KEYWORD_CANDIDATES)
          .pluck(:id)
      end
    end

    # Documents ranked by their nearest passage. Each round leaves out the
    # documents already found, so one long document cannot fill every
    # candidate, and a document from a later round is never nearer than one
    # from an earlier round.
    def semantic_ids
      vector = Embedder.embed_query(query)
      ids = []
      Chunk.transaction do
        Chunk.connection.execute("SET LOCAL hnsw.iterative_scan = strict_order") if self.class.iterative_scan?
        SEMANTIC_ROUNDS.times do
          found = Chunk.where(document_id: @scope.select(:id)).where.not(document_id: ids)
            .nearest_neighbors(:embedding, vector, distance: "cosine")
            .limit(SEMANTIC_BATCH)
            .pluck(:document_id)
          ids |= found
          break if ids.size >= SEMANTIC_CANDIDATES || found.size < SEMANTIC_BATCH
        end
      end
      ids.first(SEMANTIC_CANDIDATES)
    rescue StandardError => error
      Rails.logger.warn("[search] semantic search unavailable: #{error.message}")
      []
    end
end
