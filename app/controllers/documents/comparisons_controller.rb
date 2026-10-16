# Side-by-side view of a document and the one it looks like a copy of, so
# someone can decide which to keep.
class Documents::ComparisonsController < ApplicationController
  include DocumentScoped

  def show
    @other = params[:other].present? ? Document.find_by(id: params[:other]) : @document.duplicate_of

    redirect_to @document, notice: "This document is not flagged as a duplicate." if @other.nil? || @other == @document
  end
end
