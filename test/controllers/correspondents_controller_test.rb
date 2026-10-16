require "test_helper"

class CorrespondentsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "creates a correspondent with auto-match" do
    get new_correspondent_path
    assert_select "input[type=checkbox][name='correspondent[auto_match]']"
    assert_select "input[name='correspondent[private_documents]']", count: 0

    post correspondents_path, params: { correspondent: { name: "City Hospital", auto_match: "1" } }

    assert_redirected_to correspondents_path
    assert Correspondent.named("City Hospital").auto_match?
  end

  test "the auto-match text offers one rule link, filled in from the name" do
    { correspondents(:city_clinic) => :correspondent_id, document_types(:invoice) => :document_type_id, tags(:taxes) => :tag_ids }.each do |record, key|
      get polymorphic_path(record, action: :edit)
      action = { key => (key == :tag_ids ? [ record.id ] : record.id) }
      href = new_rule_path(rule: { name: record.name, conditions: [ { field: "content", operator: "phrase", value: record.name } ], **action })

      assert_select "form a[href=?]", href, text: "create a rule", count: 1
      assert_select "form a[href=?]", rules_path, count: 0
      assert_no_match(/Off by default/, response.body)
    end

    get new_tag_path
    assert_select "a[href=?]", new_rule_path, text: "create a rule"
  end

  test "new document types and tags match by name unless turned off" do
    assert DocumentType.create!(name: "Lease").auto_match?
    assert Tag.create!(name: "Garden").auto_match?
  end

  test "turns auto-match off" do
    patch correspondent_path(correspondents(:acme_power)), params: { correspondent: { auto_match: "0" } }

    refute correspondents(:acme_power).reload.auto_match?
  end
end
