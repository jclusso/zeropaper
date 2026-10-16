# "These are not the same": hides a suggested pair for good.
module TaxonomyMergeDismissals
  extend ActiveSupport::Concern
  include TaxonomyNested

  def create
    first, second = resource_class.where(id: [ params[:keep_id], params[:merge_id] ]).to_a
    MergeDismissal.dismiss!(first, second) if first && second

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("similar_names", partial: "taxonomy/similar_names_card", locals: { pairs: resource_class.similar_pairs }) }
      format.html { redirect_to records_path, status: :see_other }
    end
  end
end
