class Documents::ReviewsController < ApplicationController
  include DocumentScoped

  def create
    @document.review_checked!
    redirect_back_or_to inbox_path, notice: @document.needs_review? ? "Checked “#{@document.display_title}”." : "Marked “#{@document.display_title}” as reviewed."
  end
end
