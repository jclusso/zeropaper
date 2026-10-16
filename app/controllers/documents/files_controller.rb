class Documents::FilesController < ApplicationController
  include DocumentScoped, FileServing

  def show
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
end
