require "test_helper"

# Pins which names may be shown to a hosted model. A name attached only to
# private documents stays local; a name with no documents at all is shared.
class TaxonomyTest < ActiveSupport::TestCase
  setup do
    @surgeon = Correspondent.create!(name: "Secret Surgeon")
    @biopsy = DocumentType.create!(name: "Biopsy Report")
    @oncology = Tag.create!(name: "Oncology")
    secret = document_with_text("Pathology", private: true, correspondent: @surgeon, document_type: @biopsy)
    secret.tags = [ @oncology ]
  end

  test "names used only by private documents are not shareable" do
    refute_includes Correspondent.shareable, @surgeon
    refute_includes DocumentType.shareable, @biopsy
    refute_includes Tag.shareable, @oncology
  end

  test "a name also used by a shareable document is shareable" do
    shared = document_with_text("Invoice", correspondent: @surgeon, document_type: @biopsy)
    shared.tags = [ @oncology ]

    assert_includes Correspondent.shareable, @surgeon
    assert_includes DocumentType.shareable, @biopsy
    assert_includes Tag.shareable, @oncology
  end

  test "a name with no documents is shareable" do
    orphan = Tag.create!(name: "Someday")

    assert_includes Tag.shareable, orphan
  end
end

# The AI applies its answer inside a transaction that holds the document's
# row lock. A name another process creates first must not abort it.
class TaxonomyRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "a name created on another connection first is found inside a transaction" do
    Thread.new { Tag.create!(name: "Garden") }.join
    # As if the other process committed right after this one looked the
    # name up and checked it.
    lookups = 0
    Tag.define_singleton_method(:named) { |name| super(name) unless (lookups += 1) == 1 }
    Tag.any_instance.stubs(:name_unique_ignoring_case)

    tag = Tag.transaction { Tag.find_or_create_named("garden", auto_match: false) }

    assert_equal "Garden", tag.name
    assert_equal 1, Tag.where("lower(name) = 'garden'").count
  ensure
    Tag.singleton_class.remove_method(:named) if Tag.singleton_class.method_defined?(:named, false)
    Tag.where("lower(name) = 'garden'").delete_all
  end
end
