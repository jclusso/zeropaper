require "test_helper"

class FormControlsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "on/off settings are switches over real checkboxes" do
    get new_correspondent_path
    assert_select ".switch input.switch-input[type=checkbox][name='correspondent[auto_match]']"

    get edit_rule_path(rules(:taxes))
    assert_select ".switch input.switch-input[name='rule[enabled]']"
    assert_select ".switch input.switch-input[name='rule[mark_private]']"

    get settings_path
    assert_select ".switch input.switch-input[name='setting[ai_enabled]'][data-ai-gate-target=toggle][data-action='ai-gate#update']"
    assert_select ".switch input.switch-input[name='setting[searchable_pdf]']"

    get new_document_path
    assert_select ".switch input.switch-input[name=private][data-upload-target=private]"

    assert_select "input[type=checkbox].checkbox", count: 0
  end

  test "tags get a color swatch group with a live preview" do
    get edit_tag_path(tags(:taxes))

    assert_select "[data-controller=tag-preview]"
    assert_select "input.swatch[type=radio][name='tag[color]']", count: Tag::COLORS.size
    assert_select "input.swatch[type=radio][name='tag[color]'][value=red][checked][aria-label=Red]"
    assert_select "[data-tag-preview-target=chip]", text: "Taxes"
    assert_select "span", text: /generic name like/, count: 0
  end

  test "short fixed lists are plain selects with no text box; long lists are searchable" do
    get new_ai_provider_path
    assert_select "el-select[name='ai_provider[kind]'] el-option", count: AIProvider::KINDS.size
    assert_select "el-select[name='ai_provider[kind]'] input", count: 0
    assert_select "[data-controller=combobox]:has(input[name='ai_provider[kind]'])", count: 0

    get documents_path
    assert_select "el-select[name=privacy]"
    assert_select "el-select[name=status] el-option[value='']", text: "Any"
    assert_select "[data-controller=combobox] input[type=hidden][name=correspondent_id]"
    assert_select "[data-controller~=multi-select] input[type=checkbox][name='tag_ids[]']"
    assert_select "[data-controller~=multi-select] input[type=checkbox][name='document_type_ids[]']"

    get new_rule_path
    assert_select "[data-rule-conditions-target=row] el-select[name$='[field]']"
    assert_select "[data-controller=combobox][data-combobox-creatable-value=true] input[type=hidden][name='rule[correspondent_name]']"
  end

  test "switches save on and off" do
    patch tag_path(tags(:taxes)), params: { tag: { color: "sky", auto_match: "1" } }
    assert_equal "sky", tags(:taxes).reload.color
    assert tags(:taxes).auto_match?

    patch rule_path(rules(:taxes)), params: { rule: { enabled: "0" } }
    refute rules(:taxes).reload.enabled?
  end

  test "names of things are not autofilled with contacts" do
    { new_rule_path => "rule[name]", new_correspondent_path => "correspondent[name]", new_tag_path => "tag[name]",
      new_document_type_path => "document_type[name]" }.each do |path, name|
      get path
      assert_select "input[name='#{name}'][autocomplete=off][data-1p-ignore][data-lpignore][data-bwignore][data-form-type=other]"
    end

    get new_user_path
    assert_select "input[name='user[name]'][data-1p-ignore]", count: 0
  end

  test "new and edit pages for names are titled in Title Case" do
    get new_document_type_path
    assert_select "h1", text: "New Document Type"

    get edit_correspondent_path(correspondents(:acme_power))
    assert_select "h1", text: "Edit Correspondent"
  end
end
