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

  def taxonomy_documents_path(record)
    key = FILTER_KEYS[record.class.name]
    documents_path(key => (key.end_with?("_ids") ? [ record.id ] : record.id)) if key
  end
end
