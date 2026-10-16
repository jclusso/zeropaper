class Documents::DuplicateDismissalsController < ApplicationController
  include DocumentScoped

  def create
    @document.update!(duplicate_of: nil)
    @document.review_resolved!("possible_duplicate")
    redirect_back_or_to @document, notice: "Kept as a separate document."
  end
end
