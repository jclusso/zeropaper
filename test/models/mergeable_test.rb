require "test_helper"

class MergeableTest < ActiveSupport::TestCase
  test "merging tags moves documents and rules and removes the old tag" do
    car = Tag.create!(name: "Car")
    vehicle = Tag.create!(name: "Vehicle")
    both = document_with_text("Registration renewal", tags: [ car, vehicle ])
    only_vehicle = document_with_text("Inspection report", tags: [ vehicle ])
    rule = Rule.create!(name: "Cars", conditions: [ { field: "content", operator: "any", value: "vin" } ], tag_ids: [ vehicle.id, car.id ])

    vehicle.merge_into!(car)

    refute Tag.exists?(vehicle.id)
    assert_equal [ car ], both.reload.tags.to_a
    assert_equal [ car ], only_vehicle.reload.tags.to_a
    assert_equal [ car.id ], rule.reload.tag_ids
  end

  test "merging correspondents keeps documents private when either was" do
    clinic = correspondents(:city_clinic)
    other = Correspondent.create!(name: "City Clinic Billing")
    letter = document_with_text("Bill", correspondent: other)

    clinic.merge_into!(other)

    assert_equal other, letter.reload.correspondent
    assert other.reload.private_documents?
    refute Correspondent.exists?(clinic.id)
  end

  test "merging types moves documents and rules" do
    bill = DocumentType.create!(name: "Bill")
    document = document_with_text("Water bill", document_type: bill)
    rule = Rule.create!(name: "Bills", conditions: [ { field: "content", operator: "any", value: "bill" } ], document_type: bill)

    bill.merge_into!(document_types(:invoice))

    assert_equal document_types(:invoice), document.reload.document_type
    assert_equal document_types(:invoice), rule.reload.document_type
  end

  test "a record cannot merge into itself" do
    assert_raises(ArgumentError) { tags(:taxes).merge_into!(tags(:taxes)) }
  end

  test "similar names are suggested, keeping the one with more documents" do
    statement = Tag.create!(name: "Statement")
    bank = Tag.create!(name: "Bank Statement")
    document_with_text("one", tags: [ statement ])
    document_with_text("two", tags: [ statement ])
    Embedder.stubs(:embed_documents).returns([])

    pair = Tag.similar_pairs.find { |candidate| [ candidate.keep, candidate.merge ].map(&:name).sort == [ "Bank Statement", "Statement" ] }

    assert pair
    assert_equal statement, pair.keep
    assert_equal bank, pair.merge
    assert_equal "Similar spelling", pair.reason
  end

  test "dismissed suggestions stay hidden" do
    a = Tag.create!(name: "Statement")
    b = Tag.create!(name: "Bank Statement")
    Embedder.stubs(:embed_documents).returns([])

    MergeDismissal.dismiss!(a, b)

    assert_empty Tag.similar_pairs.select { |pair| [ pair.keep, pair.merge ].map(&:id).sort == [ a.id, b.id ].sort }
  end

  test "AI picks only existing types and tags when creating is off" do
    configure_openai(ai_creates_types: false, ai_creates_tags: false)
    document = ingest(BILL_TEXT, filename: "bill.txt")

    VCR.use_cassette("metadata/openai_electricity_bill") { process(document) }

    assert_equal document_types(:invoice), document.document_type
    assert_equal [ "Utilities" ], document.tags.map(&:name)
    refute Tag.exists?(name: "Electricity")
  end

  test "suggestions skip names that only share a brand and catch plurals" do
    %w[BMW\ M3 BMW\ X5\ M bmw\ M240i Car Cars Utility Utilities].each { |name| Tag.find_or_create_named(name) }
    Embedder.stubs(:embed_documents).returns([])

    pairs = Tag.similar_pairs.map { |pair| [ pair.keep.name, pair.merge.name ].sort }

    assert_includes pairs, %w[Car Cars]
    assert_includes pairs, %w[Utilities Utility]
    refute_includes pairs, [ "BMW M3", "BMW X5 M" ]
  end
end
