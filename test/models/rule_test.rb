require "test_helper"

class RuleTest < ActiveSupport::TestCase
  test "text conditions match whole words, ignoring case" do
    document = document_with_text("Your IBAN statement is attached", filename: "chase-2026.pdf")

    assert rule(field: "content", operator: "any", value: "iban, swift").matches?(document)
    assert rule(field: "content", operator: "all", value: "iban statement").matches?(document)
    refute rule(field: "content", operator: "all", value: "iban invoice").matches?(document)
    assert rule(field: "content", operator: "phrase", value: "IBAN statement").matches?(document)
    refute rule(field: "content", operator: "phrase", value: "BAN").matches?(document)
    assert rule(field: "filename", operator: "regex", value: 'chase-\d{4}').matches?(document)
  end

  test "match mode decides between all and any conditions" do
    document = document_with_text("Statement", filename: "other.pdf")
    conditions = [ { field: "content", operator: "any", value: "statement" }, { field: "filename", operator: "any", value: "chase" } ]

    refute Rule.new(conditions: conditions, match_mode: "all").matches?(document)
    assert Rule.new(conditions: conditions, match_mode: "any").matches?(document)
  end

  test "source conditions compare the ingest source" do
    document = document_with_text("anything", source: "folder")

    assert rule(field: "source", operator: "is", value: "folder").matches?(document)
    refute rule(field: "source", operator: "is", value: "upload").matches?(document)
  end

  test "validates conditions and actions" do
    empty = Rule.new(name: "Nothing")
    refute empty.valid?
    assert_includes empty.errors[:conditions], "need at least one condition"
    assert_includes empty.errors[:base], "Choose at least one thing for the rule to do"

    bad = Rule.new(name: "Bad", mark_private: true, conditions: [ { field: "filename", operator: "regex", value: "(" } ])
    refute bad.valid?
    assert_match "invalid pattern", bad.errors[:conditions].join

    source = Rule.new(name: "Source", mark_private: true, conditions: [ { field: "source", operator: "any", value: "folder" } ])
    refute source.valid?
  end

  test "blank condition rows are dropped" do
    rule = Rule.create!(name: "Tax", mark_private: true,
      conditions: [ { field: "filename", operator: "any", value: "tax" }, { field: "content", operator: "any", value: "" } ])

    assert_equal [ { "field" => "filename", "operator" => "any", "value" => "tax" } ], rule.conditions
  end

  test "filing sets correspondent, type and tags, and respects manual edits" do
    rule = Rule.create!(name: "Chase", conditions: [ { field: "content", operator: "any", value: "chase" } ],
      correspondent: correspondents(:acme_power), document_type: document_types(:letter), tag_ids: [ tags(:taxes).id ])
    document = document_with_text("Chase letter", document_type: document_types(:invoice))

    rule.apply_filing(document, overwrite: false)
    assert_equal correspondents(:acme_power), document.correspondent
    assert_equal document_types(:invoice), document.document_type
    assert_equal [ tags(:taxes) ], document.tags.to_a

    rule.apply_filing(document, overwrite: true)
    assert_equal document_types(:letter), document.document_type
  end

  test "rules run before content only when they do not need the text" do
    Rule.create!(name: "Filename", mark_private: true, conditions: [ { field: "filename", operator: "any", value: "tax" } ])
    Rule.create!(name: "Content", mark_private: true, conditions: [ { field: "content", operator: "any", value: "tax" } ])
    document = Document.new(original_filename: "tax.pdf", source: "upload")

    assert_equal [ "Filename" ], Rule.matching_before_content(document).map(&:name)
  end

  test "disabled rules never match" do
    Rule.create!(name: "Off", enabled: false, mark_private: true, conditions: [ { field: "filename", operator: "any", value: "tax" } ])

    assert_empty Rule.matching(Document.new(original_filename: "tax.pdf"))
  end

  test "auto-match files private documents by name without rules" do
    document = process(ingest("Invoice from Acme Power, amount due $12", filename: "scan_0002.txt", private: true))

    assert_equal correspondents(:acme_power), document.correspondent
    assert_equal document_types(:invoice), document.document_type
    assert_equal "Invoice from Acme Power, Amount Due $12", document.title
    assert_no_external_requests
  end

  test "correspondents, types and tags match by name unless turned off" do
    assert Correspondent.new.auto_match?
    assert Tag.new.auto_match?
    assert DocumentType.new.auto_match?

    car = Tag.create!(name: "Car")
    Tag.create!(name: "Garden", auto_match: false)
    document = process(ingest("Letter from Acme Power about the car park and the garden", filename: "letter.txt", private: true))
    assert_equal [ car ], document.tags.to_a
  end

  test "auto-match can be turned off" do
    correspondents(:acme_power).update!(auto_match: false)
    document = process(ingest("Letter from Acme Power", filename: "letter.txt", private: true))

    assert_nil document.correspondent
  end

  private
    def rule(**condition)
      Rule.new(name: "Test", mark_private: true, conditions: [ condition ])
    end
end
