class CorrespondentsController < ApplicationController
  include TaxonomyResource

  private
    def resource_class = Correspondent
    def permitted_attributes = %i[ name auto_match ]
    def document_counts = Document.group(:correspondent_id).count
end
