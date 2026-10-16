require "test_helper"

class RulesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "index summarizes each rule" do
    get rules_path

    assert_response :success
    assert_select "p", text: "Bills are invoices"
    assert_match "invoice, amount due", response.body
  end

  test "creates a rule from condition rows and actions" do
    assert_difference -> { Rule.count } do
      post rules_path, params: { rule: {
        name: "Bank statements", enabled: "1", match_mode: "all", mark_private: "1",
        correspondent_id: correspondents(:acme_power).id, document_type_id: "",
        tag_ids: [ "", tags(:utilities).id.to_s ],
        conditions: {
          "0" => { field: "content", operator: "all", value: "statement IBAN" },
          "1700000000000" => { field: "source", operator: "is", value: "folder" }
        }
      } }
    end

    rule = Rule.order(:id).last
    assert_redirected_to rules_path
    assert rule.mark_private?
    assert_equal correspondents(:acme_power), rule.correspondent
    assert_nil rule.document_type
    assert_equal [ tags(:utilities).id ], rule.tag_ids
    assert_equal [ %w[content all statement\ IBAN], %w[source is folder] ], rule.conditions.map { |condition| condition.values_at("field", "operator", "value") }
  end

  test "an invalid rule shows its errors" do
    assert_no_difference -> { Rule.count } do
      post rules_path, params: { rule: { name: "Nothing", match_mode: "all", conditions: { "0" => { field: "content", operator: "any", value: "x" } } } }
    end

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /at least one thing/
  end

  test "edits and deletes a rule" do
    rule = rules(:taxes)

    get edit_rule_path(rule)
    assert_response :success
    assert_select "el-select[name='rule[match_mode]']"
    assert_select "[data-controller=chip-input][data-chip-input-creatable-value=false] [data-chip-input-target=token] input[name='rule[tag_ids][]'][value='#{tags(:taxes).id}']"
    assert_select "[data-rule-conditions-target=row] el-select[name='rule[conditions][0][field]'][value=content]"

    patch rule_path(rule), params: { rule: { name: "Tax papers", conditions: { "0" => { field: "filename", operator: "regex", value: "tax.*pdf" } } } }
    assert_redirected_to rules_path
    assert_equal "Tax papers", rule.reload.name
    assert_equal "filename", rule.conditions.first["field"]

    assert_difference -> { Rule.count }, -1 do
      delete rule_path(rule)
    end
  end

  test "members can see rules but not change them" do
    sign_in_as users(:two)

    get rules_path
    assert_response :success
    assert_select "a", text: "Edit", count: 0

    get new_rule_path
    assert_response :forbidden
  end
end
