class Documents::FilesController < ApplicationController
  include DocumentScoped, FileServing

  def show
    return show_pages if params[:variant] == "viewable" && params[:pages].present?

    attachment =
      case params[:variant]
      when "best" then @document.best_download
      when "upload" then @document.original_download
      when "original" then @document.original_file
      when "archive" then @document.archive_file
      when "viewable" then @document.viewable_pdf
      else @document.file
      end
    return head(:not_found) unless attachment&.attached?

    send_attachment attachment, disposition: params[:download] ? :attachment : :inline
  end

  private
    # Some pages of the viewable PDF, for a comparison's preview.
    def show_pages
      pages = params[:pages].to_s.split(",").map(&:to_i).uniq.sort
      return head(:not_found) unless @document.viewable_pdf&.attached? && pages.any? && pages.all? { it.between?(1, @document.page_count.to_i) }

      send_pdf_data @document.viewable_pdf_with(pages), filename: @document.viewable_pdf.blob.filename.to_s
    end
end
