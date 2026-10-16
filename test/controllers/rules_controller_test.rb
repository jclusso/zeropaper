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

  test "names typed in the pickers are created and assigned" do
    assert_difference -> { Correspondent.count } => 1, -> { DocumentType.count } => 1, -> { Tag.count } => 1 do
      post rules_path, params: { rule: {
        name: "Dentist", match_mode: "all", correspondent_name: "Harbor Dental", document_type_name: "Appointment card",
        tag_names: [ "", "Health", "utilities" ],
        conditions: { "0" => { field: "content", operator: "phrase", value: "Harbor Dental" } }
      } }
    end

    rule = Rule.order(:id).last
    assert_redirected_to rules_path
    assert_equal "Harbor Dental", rule.correspondent.name
    assert_equal "Appointment card", rule.document_type.name
    assert_equal [ "Health", "Utilities" ], rule.tags.map(&:name).sort
  end

  test "leaving the pickers empty sets nothing" do
    rule = rules(:taxes)

    patch rule_path(rule), params: { rule: { correspondent_name: "", document_type_name: "", tag_names: [ "" ], mark_private: "1" } }

    rule.reload
    assert_nil rule.correspondent
    assert_nil rule.document_type
    assert_empty rule.tag_ids
  end

  test "a link can prefill a new rule" do
    get new_rule_path(rule: { name: "Acme Power", conditions: [ { field: "content", operator: "phrase", value: "Acme Power" } ],
      correspondent_id: correspondents(:acme_power).id, document_type_id: document_types(:invoice).id, tag_ids: [ tags(:utilities).id, 0 ] })

    assert_response :success
    assert_select "input[name='rule[name]'][value='Acme Power']"
    assert_select "el-select[name='rule[conditions][0][operator]'][value=phrase]"
    assert_select "input[name='rule[conditions][0][value]'][value='Acme Power']"
    assert_select "input[type=hidden][name='rule[correspondent_name]'][value='Acme Power']"
    assert_select "input[type=hidden][name='rule[document_type_name]'][value='Invoice']"
    assert_select "[data-chip-input-target=token] input[name='rule[tag_names][]'][value='Utilities']"
  end

  test "a prefill with unknown ids still opens the form" do
    get new_rule_path(rule: { correspondent_id: 0, document_type_id: 0, tag_ids: [ 0 ] })

    assert_response :success
    assert_select "input[type=hidden][name='rule[correspondent_name]']" do |inputs|
      assert inputs.first["value"].blank?
    end
    assert_select "[data-rule-conditions-target=list] [data-rule-conditions-target=row]", count: 1
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
    assert_select "[data-controller=chip-input][data-chip-input-creatable-value=true] [data-chip-input-target=token] input[name='rule[tag_names][]'][value='Taxes']"
    assert_select "p.hint", text: /Choose from existing tags/, count: 0
    assert_select "[data-rule-conditions-target=row] el-select[name='rule[conditions][0][field]'][value=content]"

    patch rule_path(rule), params: { rule: { name: "Tax papers", conditions: { "0" => { field: "filename", operator: "regex", value: "tax.*pdf" } } } }
    assert_redirected_to rules_path
    assert_equal "Tax papers", rule.reload.name
    assert_equal "filename", rule.conditions.first["field"]

    assert_difference -> { Rule.count }, -1 do
      delete rule_path(rule)
    end
  end

  test "a rule turned off because its tag was deleted says so" do
    tags(:taxes).destroy!

    get rules_path

    assert_select "li", text: /Tax returns.*Turned off because what it set was deleted/m
    assert_select "p", text: /Turned off because what it set was deleted/, count: 1
  end

  test "members can see rules but not change them" do
    sign_in_as users(:two)

    get rules_path
    assert_response :success
    assert_select "a", text: "Edit", count: 0

    get new_rule_path
    assert_response :forbidden
  end

  test "the enabled switch sits in the header and still belongs to the form" do
    rule = rules(:clinic_private)

    get edit_rule_path(rule)

    assert_select "form#rule_form"
    assert_select "form#rule_form input[name='rule[enabled]']", count: 0
    assert_select "input[type=hidden][name='rule[enabled]'][value='0'][form=rule_form]"
    assert_select "input[type=checkbox]#rule_enabled[name='rule[enabled]'][form=rule_form]"

    patch rule_path(rule), params: { rule: { enabled: "0" } }
    refute rule.reload.enabled?
  end

  test "saving a mark-private rule says existing documents are being marked private" do
    post rules_path, params: { rule: { name: "Medical", match_mode: "all", mark_private: "1",
      conditions: { "0" => { field: "content", operator: "any", value: "diagnosis" } } } }

    assert_redirected_to rules_path
    assert_equal "Rule added. Matching documents already in the library are being marked private.", flash[:notice]
    assert_enqueued_with(job: PrivatizeRuleMatchesJob, args: [ Rule.order(:id).last ])

    patch rule_path(Rule.order(:id).last), params: { rule: { name: "Health" } }
    assert_equal "Rule saved.", flash[:notice]
  end

  test "saving a mark-private rule does not read the library during the request" do
    document_with_text("Diagnosis: seasonal allergies")
    Rule.any_instance.expects(:matches?).never

    post rules_path, params: { rule: { name: "Medical", match_mode: "all", mark_private: "1",
      conditions: { "0" => { field: "content", operator: "any", value: "diagnosis" } } } }

    assert_redirected_to rules_path
    assert_equal 1, Document.shareable.count
  end
end
