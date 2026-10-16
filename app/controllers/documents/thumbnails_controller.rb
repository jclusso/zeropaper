class Documents::ThumbnailsController < ApplicationController
  include DocumentScoped, FileServing

  def show
    if @document.thumbnail.attached?
      send_attachment @document.thumbnail
    else
      head :not_found
    end
  end
end
