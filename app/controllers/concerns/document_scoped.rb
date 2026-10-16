module DocumentScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_document
  end

  private
    def set_document
      @document = Document.find(params[:document_id])
    end
end
