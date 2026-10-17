class Backups::RestorationsController < ApplicationController
  require_admin

  def create
    backup = Backup.stored.find_by(id: params[:backup_id])
    return redirect_to(backups_path, alert: "That backup is no longer listed.") unless backup

    restore = Restore.new(user: Current.user, filename: backup.filename, key: params[:backup_key].presence)
    if restore.save
      restore.process_later
      redirect_to backups_path(anchor: "restores"), notice: "Restoring #{restore.filename}."
    else
      redirect_to backups_path, alert: restore.errors.full_messages.to_sentence
    end
  end
end
