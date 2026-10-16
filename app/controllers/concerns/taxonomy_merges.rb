# Merging one correspondent, document type or tag into another.
module TaxonomyMerges
  extend ActiveSupport::Concern
  include TaxonomyNested

  included do
    before_action :set_record
  end

  def new
    counted = resource_class.with_document_counts
    @documents_count = counted.find(@record.id).documents_count.to_i
    @targets = counted.where.not(id: @record.id).sort_by { |target| target.name.downcase }
    render "taxonomy/merges/new"
  end

  def create
    target = resource_class.find_by(id: params[:target_id])
    name = @record.name
    @record.merge_into!(target)
    redirect_to records_path, notice: "Merged “#{name}” into “#{target.name}”.", status: :see_other
  rescue ArgumentError => error
    redirect_to polymorphic_path([ :new, @record, :merge ]), alert: error.message, status: :see_other
  end

  private
    def set_record
      @record = resource_class.find(params[:"#{resource_class.model_name.singular}_id"])
    end
end
