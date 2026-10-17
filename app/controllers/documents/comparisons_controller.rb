# Side-by-side view of a document and the one it looks like a copy of, so
# someone can decide which to keep.
class Documents::ComparisonsController < ApplicationController
  include DocumentScoped

  def show
    @other = params[:other].present? ? Document.find_by(id: params[:other]) : @document.duplicate_of

    if @other.nil? || @other == @document
      redirect_to @document, notice: "This document is not flagged as a duplicate."
    elsif turbo_frame_request?
      # Both documents' viewers, loaded into the side-by-side dialog when it opens.
      render :viewers
    end
  end
end
