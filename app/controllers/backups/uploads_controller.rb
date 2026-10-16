class Backups::UploadsController < ApplicationController
  require_admin

  def create
    upload = params[:archive]
    return redirect_to(backups_path, alert: "Choose a ZeroPaper backup.") unless upload.respond_to?(:path)

    path = Backup.import(upload.path)
    redirect_to backups_path, notice: "Added #{path.basename}. Restore it from the list."
  rescue Archive::Reader::InvalidArchive => error
    redirect_to backups_path, alert: error.message
  end
end
