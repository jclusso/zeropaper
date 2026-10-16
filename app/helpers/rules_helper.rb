module RulesHelper
  # "text contains any of: statement, IBAN and filename matches the pattern: chase"
  def rule_conditions_summary(rule)
    parts = rule.conditions.map do |condition|
      field = Rule::FIELDS.fetch(condition["field"], condition["field"]).downcase
      value = condition["field"] == "source" ? Rule::SOURCES.fetch(condition["value"], condition["value"]) : condition["value"]
      safe_join([ "#{field} #{Rule::OPERATORS.fetch(condition["operator"], condition["operator"])} ", tag.code(value, class: "text-foreground") ])
    end
    safe_join(parts, rule.match_mode == "any" ? " or " : " and ")
  end

  # "Chase, Statement, +Finance, private"
  def rule_actions_summary(rule)
    parts = []
    parts << safe_join([ "correspondent ", tag.span(rule.correspondent.name, class: "font-bold text-foreground") ]) if rule.correspondent
    parts << safe_join([ "type ", tag.span(rule.document_type.name, class: "font-bold text-foreground") ]) if rule.document_type
    rule.tags.each { |rule_tag| parts << tag_chip(rule_tag, link: false) }
    parts << private_badge if rule.mark_private?
    parts.any? ? safe_join(parts, ", ") : tag.span("Nothing", class: "muted")
  end
end
