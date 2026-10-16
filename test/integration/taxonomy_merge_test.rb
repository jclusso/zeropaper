require "test_helper"

class TaxonomyMergeTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    Embedder.stubs(:embed_documents).returns([])
    @statement = Tag.create!(name: "Statement")
    @bank = Tag.create!(name: "Bank Statement")
    @first = document_with_text("one", tags: [ @statement ])
    @second = document_with_text("two", tags: [ @bank ])
  end

  test "the list page loads similar names lazily and offers Merge into" do
    get tags_path

    assert_select "turbo-frame#similar_names[src='#{tag_similar_names_path}'][loading=lazy]"
    assert_select "a[href='#{new_tag_merge_path(@bank)}']", text: "Merge into…"
  end

  test "similar names suggests the pair, keeping the one with more documents" do
    document_with_text("three", tags: [ @statement ])

    get tag_similar_names_path

    assert_select "turbo-frame#similar_names" do
      assert_select "#similar_pair_#{[ @statement.id, @bank.id ].minmax.join("_")}" do
        assert_select "form[action='#{tag_merge_path(@bank)}'][data-turbo-confirm-button='Merge'][data-turbo-frame='_top'] button", text: "Merge"
        assert_select "form[action='#{tag_merge_path(@statement)}'] button", text: "Keep “Bank Statement” instead"
        assert_select "form[action='#{tag_merge_dismissals_path}'] button", text: "Dismiss"
        assert_select ".badge-slate", text: "Similar spelling"
      end
      # Names of the same length are not "contained" in each other.
      assert_select "#similar_pair_#{[ tags(:utilities).id, @statement.id ].minmax.join("_")}", count: 0
    end
  end

  test "merging moves documents and says so" do
    post tag_merge_path(@bank), params: { target_id: @statement.id }

    assert_redirected_to tags_path
    assert_equal "Merged “Bank Statement” into “Statement”.", flash[:notice]
    refute Tag.exists?(@bank.id)
    assert_equal [ @statement ], @second.reload.tags.to_a
  end

  test "merging into itself is refused with an alert" do
    post tag_merge_path(@bank), params: { target_id: @bank.id }

    assert_redirected_to new_tag_merge_path(@bank)
    assert flash[:alert].present?
    assert Tag.exists?(@bank.id)
  end

  test "the merge page lets you pick any other record" do
    get new_tag_merge_path(@bank)

    assert_response :success
    assert_select "form[action='#{tag_merge_path(@bank)}'][data-turbo-confirm]"
    assert_select "input[type=hidden][name=target_id]"
    assert_select "el-option", text: /Statement \(1 document\)/
    assert_select "el-option", text: /Bank Statement/, count: 0
  end

  test "correspondent merges say rules move with it" do
    get new_correspondent_merge_path(correspondents(:city_clinic))

    assert_select "li", text: /Rules that set or add it/
    assert_select "li", text: /keep documents private/, count: 0
  end

  test "dismissing hides the pair" do
    post tag_merge_dismissals_path, params: { keep_id: @statement.id, merge_id: @bank.id }, as: :turbo_stream

    assert_response :success
    assert MergeDismissal.exists?(kind: "Tag")
    assert_no_match "similar_pair_#{[ @statement.id, @bank.id ].minmax.join("_")}", response.body
  end

  test "document types merge too" do
    bill = DocumentType.create!(name: "Bill")
    document = document_with_text("Water bill", document_type: bill)

    post document_type_merge_path(bill), params: { target_id: document_types(:invoice).id }

    assert_redirected_to document_types_path
    assert_equal document_types(:invoice), document.reload.document_type
  end
end
