class DocumentTypesController < ApplicationController
  include TaxonomyResource

  private
    def resource_class = DocumentType
    def permitted_attributes = %i[ name auto_match ]
    def document_counts = Document.group(:document_type_id).count
end
