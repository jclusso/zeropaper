class BackupsController < ApplicationController
  layout "admin"

  require_admin

  def index
    @setting = Setting.instance
    @files = Backup.files
    @unfinished = Backup.unfinished.includes(:user)
    @restores = Restore.recent.includes(:user).limit(5)
  end

  def create
    backup = Backup.create!(user: Current.user)
    backup.process_later
    redirect_to backups_path, notice: "Backup started. It will be listed here when it is ready."
  end

  def show
    file = Backup.file_for(params[:id])
    return redirect_to(backups_path, alert: "That backup is no longer in the backup folder.") unless file

    response.headers["Cache-Control"] = "private, no-store"
    send_file file, filename: file.basename.to_s, type: "application/octet-stream"
  end

  def destroy
    file = Backup.file_for(params[:id])
    file&.delete
    redirect_to backups_path, notice: file ? "Deleted #{file.basename}." : "That backup was already gone."
  end
end
