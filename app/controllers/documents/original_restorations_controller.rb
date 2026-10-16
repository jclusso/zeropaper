class Documents::OriginalRestorationsController < ApplicationController
  include DocumentScoped

  def create
    @document.restore_original!
    redirect_to @document, notice: "Original restored. Reading it again."
  rescue Document::Pages::EditRefused => error
    redirect_to @document, alert: error.message
  end
end
