# Lists taxonomy names with their document counts. The documents behind the
# counts are registered with the research, so each later request checks them
# again and the answer records them.
class Research::ListTaxonomy < Research::Tool
  description "Lists the correspondents, document types and tags in the archive with how many documents each has."

  def execute
    research.shareable(filed_documents)
    {
      correspondents: counts(Correspondent, :documents),
      document_types: counts(DocumentType, :documents),
      tags: counts(Tag, :documents)
    }
  end

  private
    def counts(model, association)
      model.shareable.left_joins(association).where(documents: { private: [ false, nil ] })
        .group(:name).order(Arel.sql("count(documents.id) desc")).limit(200).count("documents.id")
    end

    # Shareable documents with a correspondent, type or tag.
    def filed_documents
      Document.shareable.where.not(correspondent_id: nil)
        .or(Document.shareable.where.not(document_type_id: nil))
        .or(Document.shareable.where(id: Tagging.select(:document_id)))
        .select(:id, :private).to_a
    end
end
