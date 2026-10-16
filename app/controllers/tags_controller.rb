class TagsController < ApplicationController
  include TaxonomyResource

  private
    def resource_class = Tag
    def permitted_attributes = %i[ name color auto_match ]
    def document_counts = Tagging.group(:tag_id).count
end
