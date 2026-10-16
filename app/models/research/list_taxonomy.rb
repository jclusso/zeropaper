class Research::ListTaxonomy < Research::Tool
  description "Lists the correspondents, document types and tags in the archive with how many documents each has."

  def execute
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
end
