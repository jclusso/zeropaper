class Documents::OriginalRestorationsController < ApplicationController
  include DocumentScoped
  rate_limit to: 30, within: 1.minute, only: :create, scope: "document-edits", by: -> { Current.user.id },
    with: -> { redirect_to @document, alert: "Too many changes at once. Wait a minute and try again." }

  def create
    @document.restore_original!
    redirect_to @document, notice: "Original restored. Reading it again."
  rescue Document::Pages::EditRefused => error
    redirect_to @document, alert: error.message
  end
end
