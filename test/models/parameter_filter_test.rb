require "test_helper"

class ParameterFilterTest < ActiveSupport::TestCase
  FILTERED = "[FILTERED]".freeze

  setup { @filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  test "document details, searches, questions, filenames and rule conditions are filtered" do
    filtered = @filter.filter(
      "document" => { "title" => "Biopsy results", "summary" => "Benign", "correspondent_name" => "City Clinic", "tag_names" => [ "Oncology" ] },
      "q" => "divorce lawyer",
      "query" => "custody",
      "question" => "What did the clinic find?",
      "message" => { "content" => "Follow up on the biopsy" },
      "files" => [ "scan.pdf" ],
      "original_filename" => "biopsy.pdf",
      "rule" => { "name" => "Medical", "conditions" => [ { "field" => "content", "operator" => "contains", "value" => "SSN 123" } ] }
    )

    assert_equal FILTERED, filtered.dig("document", "title")
    assert_equal FILTERED, filtered.dig("document", "summary")
    assert_equal FILTERED, filtered.dig("document", "correspondent_name")
    assert_equal FILTERED, filtered.dig("document", "tag_names")
    assert_equal FILTERED, filtered["q"]
    assert_equal FILTERED, filtered["query"]
    assert_equal FILTERED, filtered["question"]
    assert_equal FILTERED, filtered.dig("message", "content")
    assert_equal FILTERED, filtered["files"]
    assert_equal FILTERED, filtered["original_filename"]
    assert_equal FILTERED, filtered.dig("rule", "conditions")
    assert_equal "Medical", filtered.dig("rule", "name")
  end

  test "existing filters stay and ordinary parameters are kept" do
    filtered = @filter.filter("password" => "secret", "email_address" => "a@example.com", "page" => "2", "view" => "grid", "quality" => "high")

    assert_equal FILTERED, filtered["password"]
    assert_equal FILTERED, filtered["email_address"]
    assert_equal "2", filtered["page"]
    assert_equal "grid", filtered["view"]
    assert_equal "high", filtered["quality"], "q is matched exactly"
  end
end
