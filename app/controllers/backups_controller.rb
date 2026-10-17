class BackupsController < ApplicationController
  layout "admin"

  require_admin

  def index
    @setting = Setting.instance
    @backups = Backup.stored.order(made_at: :desc)
    @unfinished = Backup.unfinished.includes(:user)
    @restores = Restore.recent.includes(:user).limit(5)
  end

  def create
    backup = Backup.create!(user: Current.user)
    backup.process_later
    redirect_to backups_path, notice: "Backup started. It will be listed here when it is ready."
  end

  def show
    file = Backup.stored.find_by(id: params[:id])&.path
    return gone unless file

    io = Backup.open_file(file)
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["Content-Length"] = io.size.to_s
    send_file_headers! filename: file.basename.to_s, type: "application/octet-stream", disposition: "attachment"
    self.response_body = Backup::Download.new(io)
  rescue Archive::Reader::InvalidArchive => error
    redirect_to backups_path, alert: error.message
  rescue Errno::ENOENT
    gone
  end

  def destroy
    backup = Backup.stored.find_by(id: params[:id])
    backup&.remove!
    redirect_to backups_path, notice: backup ? "Deleted #{backup.filename}." : "That backup was already gone."
  end

  private
    def gone
      redirect_to backups_path, alert: "That backup is no longer in the backup folder."
    end
end
