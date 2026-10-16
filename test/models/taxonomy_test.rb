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
