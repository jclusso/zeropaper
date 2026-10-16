require "test_helper"

class SearchTest < ActiveSupport::TestCase
  setup do
    @bill = document_with_text(BILL_TEXT, title: "Electricity statement", document_date: Date.new(2026, 3, 14), correspondent: correspondents(:acme_power))
    @letter = document_with_text("Your dental cleaning is booked for June.", title: "Dentist reminder", document_date: Date.new(2025, 6, 1))
    @diagnosis = document_with_text("Diagnosis letter about the electricity of nerves", title: "Neurology letter", private: true)
    [ @bill, @letter, @diagnosis ].each(&:index!)
  end

  test "finds documents by keyword, best match first" do
    results = Search.new(query: "electricity statement").results

    assert_equal @bill, results.first
    assert_not_includes results.first(2), @letter
  end

  test "private documents are found because search runs locally" do
    assert_includes Search.new(query: "neurology").results, @diagnosis
  end

  test "filters narrow the results" do
    results = Search.new(query: "electricity", filters: { privacy: "shareable" }).results
    assert_includes results, @bill
    assert_not_includes results, @diagnosis

    assert_equal [ @letter ], Search.new(query: "", filters: { date_to: "2025-12-31" }).results
    assert_equal [ @bill ], Search.new(query: "", filters: { correspondent_id: correspondents(:acme_power).id }).results
  end

  test "keyword search still works when embeddings are unavailable" do
    Embedder.stubs(:embed_query).raises(RuntimeError, "model missing")

    assert_equal @bill, Search.new(query: "statement").results.first
  end

  test "a misspelled title still matches by keyword" do
    Embedder.stubs(:embed_query).raises(RuntimeError, "model missing")

    assert_equal [ @letter ], Search.new(query: "dentst").results
  end

  test "a filter that hides the nearest passages still finds the documents it allows" do
    query = unit_vector(0)
    Embedder.stubs(:embed_query).returns(query)
    hidden = document_with_text("Hidden", private: true)
    60.times { |position| add_chunk(hidden, position, near(query, 0.05, seed: position)) }
    shown = 5.times.map { |index| document_with_text("Shown #{index}").tap { |document| add_chunk(document, 0, near(query, 0.5, seed: 100 + index)) } }
    # Makes the planner walk the HNSW index, as it does on a real library,
    # rather than sort this handful of rows exactly.
    Chunk.connection.execute("SET LOCAL enable_sort = off")
    Chunk.connection.execute("SET LOCAL enable_sort = off")

    ids = Search.new(query: "anything", filters: { privacy: "shareable" }).send(:semantic_ids)

    assert Search.iterative_scan?
    assert_equal shown.map(&:id).sort, (ids & shown.map(&:id)).sort, "every allowed document is found past the 40 the index returns first"
    refute_includes ids, hidden.id
  end

  test "one long document does not take every semantic candidate" do
    query = unit_vector(0)
    Embedder.stubs(:embed_query).returns(query)
    long = document_with_text("Long manual")
    100.times { |position| add_chunk(long, position, near(query, 0.05, seed: position)) }
    short = 6.times.map { |index| document_with_text("Short note #{index}").tap { |document| add_chunk(document, 0, near(query, 0.4, seed: 500 + index)) } }

    ids = Search.new(query: "anything").send(:semantic_ids)

    assert_equal long.id, ids.first
    assert_equal short.map(&:id).sort, (ids & short.map(&:id)).sort
  end

  test "without iterative scan, later rounds still find documents past the first" do
    Search.stubs(:iterative_scan?).returns(false)
    # The HNSW index, as on a library too large for a sequential scan.
    Chunk.connection.execute("SET LOCAL enable_sort = off")
    query = unit_vector(0)
    Embedder.stubs(:embed_query).returns(query)
    long = document_with_text("Long manual")
    100.times { |position| add_chunk(long, position, near(query, 0.05, seed: position)) }
    short = 6.times.map { |index| document_with_text("Short note #{index}").tap { |document| add_chunk(document, 0, near(query, 0.4, seed: 500 + index)) } }

    ids = Search.new(query: "anything").send(:semantic_ids)

    assert_equal long.id, ids.first
    assert_equal short.map(&:id).sort, (ids & short.map(&:id)).sort
  end

  test "a blank query lists documents newest first" do
    assert_equal [ @bill, @letter ], Search.new(query: " ", filters: { privacy: "shareable" }).results
  end

  private
    def unit_vector(axis)
      Array.new(Embedder::DIMENSIONS, 0.0).tap { |values| values[axis] = 1.0 }
    end

    # A vector at roughly the given distance from target, varied by seed.
    def near(target, spread, seed:)
      random = Random.new(seed)
      target.map { |value| value + (random.rand - 0.5) * spread * 0.1 }.tap { |values| values[1 + seed % 50] += spread }
    end

    def add_chunk(document, position, embedding)
      document.chunks.create!(position: position, content: "Passage #{position}", embedding: embedding)
    end
end
