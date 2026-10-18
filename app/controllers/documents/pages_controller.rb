# Page images for the viewer's thumbnail rail, the page editor and the
# comparison, which shows removed pages from the stored upload.
class Documents::PagesController < ApplicationController
  include DocumentScoped, FileServing

  EDGES = { "thumb" => 240, "large" => 900 }.freeze

  rate_limit to: 300, within: 1.minute, only: :show, by: -> { Current.user.id }

  # The page editor. The document page loads it into a dialog through a
  # Turbo Frame; opened directly it renders on its own.
  def index
    redirect_to(@document, alert: "Only PDFs have pages to edit.") unless @document.pdf?
  end

  def show
    source = { "file" => @document.file, "original" => @document.original_file }.fetch(params[:source]) { @document.viewable_pdf || @document.file }
    return head(:not_found) unless @document.pdf? && source.attached?

    page = params[:id].to_i
    pages = params[:source] == "original" ? @document.page_fingerprints(source).size : @document.page_count.to_i
    return head(:not_found) unless page.between?(1, pages)

    edge = EDGES.fetch(params[:size], EDGES["thumb"])
    send_image @document.page_image(source, page, edge: edge)
  end
end
