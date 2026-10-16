# Shared CRUD for correspondents, document types and tags.
# Each controller names its model and permitted attributes.
module TaxonomyResource
  extend ActiveSupport::Concern

  included do
    before_action :set_record, only: %i[ edit update destroy ]
    helper_method :resource_class
  end

  def index
    @records = resource_class.order(Arel.sql("lower(name)"))
    @counts = document_counts
    render "taxonomy/index"
  end

  def new
    @record = resource_class.new
    render "taxonomy/form"
  end

  def create
    @record = resource_class.new(record_params)
    if @record.save
      redirect_to url_for(action: :index), notice: "#{resource_class.model_name.human} added."
    else
      render "taxonomy/form", status: :unprocessable_entity
    end
  end

  def edit
    render "taxonomy/form"
  end

  def update
    if @record.update(record_params)
      redirect_to url_for(action: :index), notice: "#{resource_class.model_name.human} saved."
    else
      render "taxonomy/form", status: :unprocessable_entity
    end
  end

  def destroy
    @record.destroy
    redirect_to url_for(action: :index), notice: "#{resource_class.model_name.human} deleted.", status: :see_other
  end

  private
    def set_record
      @record = resource_class.find(params[:id])
    end

    def record_params
      params.expect(resource_class.model_name.param_key => permitted_attributes)
    end

    def document_counts
      {}
    end
end
