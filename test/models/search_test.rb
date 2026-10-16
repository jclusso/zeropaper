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

  test "a blank query lists documents newest first" do
    assert_equal [ @bill, @letter ], Search.new(query: " ", filters: { privacy: "shareable" }).results
  end
end
