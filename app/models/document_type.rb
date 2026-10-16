class DocumentType < ApplicationRecord
  include AutoMatchable, Taxonomy, Mergeable

  has_many :documents, dependent: :nullify

  private
    def affected_document_ids
      documents.ids
    end

    def move_to(target)
      documents.update_all(document_type_id: target.id, updated_at: Time.current)
      Rule.where(document_type_id: id).update_all(document_type_id: target.id)
    end
end
