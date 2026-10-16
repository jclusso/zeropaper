# Suggested merges for a list page, loaded into a lazy frame because
# comparing names by meaning runs the local embedding model.
module TaxonomySimilarNames
  extend ActiveSupport::Concern
  include TaxonomyNested

  def index
    render partial: "taxonomy/similar_names", locals: { pairs: resource_class.similar_pairs }
  end
end
