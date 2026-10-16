class ExportsController < ApplicationController
  layout "admin"

  include FileServing
  require_admin

  def index
    @exports = Export.order(created_at: :desc).limit(20)
  end

  def create
    export = Export.create!(user: Current.user, include_private: params[:include_private] == "1")
    export.process_later
    redirect_to exports_path, notice: "Export started. It will be ready to download here."
  end

  def show
    export = Export.find(params[:id])
    return redirect_to(exports_path, alert: "That export is not ready yet.") unless export.status == "ready" && export.archive.attached?

    send_attachment export.archive, disposition: :attachment
  end
end
