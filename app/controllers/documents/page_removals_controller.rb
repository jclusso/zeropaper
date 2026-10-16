class Documents::PageRemovalsController < ApplicationController
  include DocumentScoped
  rate_limit to: 30, within: 1.minute, only: :create, scope: "document-edits", by: -> { Current.user.id },
    with: -> { redirect_to @document, alert: "Too many changes at once. Wait a minute and try again." }

  def create
    pages = Array(params[:pages]).map(&:to_i)
    # Suggested blank pages left unchecked are kept on purpose.
    kept = @document.suggested_blank_pages - pages
    @document.remove_pages!(pages, keep_blank: kept, version: params[:version])
    redirect_to @document, notice: notice_for(pages, kept)
  rescue Document::Pages::EditRefused, Pdf::CommandFailed => error
    redirect_to @document, alert: error.message
  end

  private
    def notice_for(removed, kept)
      parts = []
      parts << "Removed #{helpers.pluralize(removed.size, "page")}" if removed.any?
      parts << "#{removed.any? ? "kept" : "Kept"} #{helpers.pluralize(kept.size, "page")} marked blank" if kept.any?
      parts.any? ? "#{parts.join(", ")}." : "Pages updated."
    end
end
