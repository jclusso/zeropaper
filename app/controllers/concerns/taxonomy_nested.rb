# For controllers nested under correspondents, document types or tags
# (Tags::MergesController and friends): works out which model they serve.
module TaxonomyNested
  extend ActiveSupport::Concern

  included do
    helper_method :resource_class
  end

  private
    def resource_class
      @resource_class ||= self.class.module_parent.name.singularize.constantize
    end

    def records_path
      polymorphic_path(resource_class)
    end
end
