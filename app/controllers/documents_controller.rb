class DocumentsController < ApplicationController
  PER_PAGE = 48

  before_action :set_document, only: %i[ show edit update destroy ]

  def index
    @filters = filter_params
    @view = params[:view] == "timeline" ? "timeline" : "grid"
    @page = [ params[:page].to_i, 1 ].max
    scope = Document.filter_by(@filters).includes(:correspondent, :document_type, :tags, thumbnail_attachment: :blob).chronologically
    @documents = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @next_page = @documents.size > PER_PAGE
    @documents = @documents.first(PER_PAGE)
    @total = Document.filter_by(@filters).count
  end

  def show
  end

  def new
  end

  def create
    files = Array(params[:files]).select { |file| file.respond_to?(:read) && file.original_filename.present? }
    results = files.map { |file| ingest(file) }

    respond_to do |format|
      format.json { render json: { results: results }, status: (results.any? ? :ok : :unprocessable_entity) }
      format.html do
        return redirect_to(new_document_path, alert: "Choose at least one file.") if results.empty?

        added = results.select { |result| result[:status] == "created" }
        skipped = results - added
        flash[:notice] = "Added #{helpers.pluralize(added.size, "document")}. Processing has started." if added.any?
        flash[:alert] = "Skipped #{helpers.pluralize(skipped.size, "file")}. #{skipped.first(5).map { |result| "#{result[:filename]}: #{result[:message]}" }.join(" · ")}" if skipped.any?
        redirect_to(added.one? ? added.first[:url] : documents_path)
      end
    end
  end

  def edit
    redirect_to @document
  end

  def update
    if @document.edit_details(document_params)
      @document.refresh_search_vector
      @document.review_checked!
      redirect_to @document, notice: "Saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    flagged = Document.where(duplicate_of: @document).to_a
    @document.destroy
    # Documents that looked like copies of this one are no longer duplicates.
    flagged.each { |document| document.review_resolved!("possible_duplicate") }

    redirect_to (Document.find_by(id: params[:then_open]) || documents_path), notice: "Deleted “#{@document.display_title}”.", status: :see_other
  end

  private
    # Adds one uploaded file and describes the outcome for the uploader.
    def ingest(file)
      filename = File.basename(file.original_filename)
      document = Document.ingest!(io: file, filename: filename, source: "upload",
        private: params[:private] == "1", private_reason: ("Marked private on upload" if params[:private] == "1"),
        uploaded_by: Current.user)
      { filename: filename, status: "created", message: "Added", title: document.display_title, url: document_path(document), private: document.private? }
    rescue Document::Duplicate => error
      { filename: filename, status: "duplicate", message: "Already in the library", title: error.document.display_title, url: document_path(error.document) }
    rescue Document::UnsupportedType
      { filename: filename, status: "unsupported", message: "Not a supported file type" }
    end

    def set_document
      @document = Document.find(params[:id])
    end

    def filter_params
      Document.filter_params(params)
    end

    def document_params
      permitted = params.expect(document: [ :title, :document_date, :summary, :correspondent_name, :document_type_name, tag_names: [] ])
      attributes = permitted.slice(:title, :document_date, :summary)
      attributes[:correspondent] = Correspondent.find_or_create_named(permitted[:correspondent_name]) if permitted.key?(:correspondent_name)
      attributes[:document_type] = DocumentType.find_or_create_named(permitted[:document_type_name]) if permitted.key?(:document_type_name)
      attributes[:tag_names] = Array(permitted[:tag_names]).map(&:squish).compact_blank if permitted.key?(:tag_names)
      attributes
    end
end
