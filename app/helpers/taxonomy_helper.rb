module TaxonomyHelper
  DESCRIPTIONS = {
    "Correspondent" => "People and organizations your documents come from.",
    "DocumentType" => "Kinds of documents, such as invoices, contracts or letters.",
    "Tag" => "Topics that cut across correspondents and types."
  }.freeze

  FILTER_KEYS = { "Correspondent" => :correspondent_id, "DocumentType" => :document_type_ids, "Tag" => :tag_ids }.freeze

  def taxonomy_title(model)
    model.model_name.human.pluralize.titleize
  end

  def taxonomy_description(model)
    DESCRIPTIONS[model.name]
  end

  # A new rule that starts from the record's name: documents containing it
  # get this correspondent, type or tag. Unsaved records have nothing to fill in.
  def new_rule_for(record)
    return new_rule_path unless record.persisted?

    action = case record
    when Correspondent then { correspondent_id: record.id }
    when DocumentType then { document_type_id: record.id }
    when Tag then { tag_ids: [ record.id ] }
    end
    new_rule_path(rule: { name: record.name, conditions: [ { field: "content", operator: "phrase", value: record.name } ], **action })
  end

  def taxonomy_documents_path(record)
    key = FILTER_KEYS[record.class.name]
    documents_path(key => (key.end_with?("_ids") ? [ record.id ] : record.id)) if key
  end
end
