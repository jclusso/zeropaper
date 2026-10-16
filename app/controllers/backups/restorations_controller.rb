class Backups::RestorationsController < ApplicationController
  require_admin

  def create
    restore = Restore.new(user: Current.user, filename: "#{params[:backup_id]}#{Backup::EXTENSION}", key: params[:key].presence)
    if restore.save
      restore.process_later
      redirect_to backups_path(anchor: "restores"), notice: "Restoring #{restore.filename}."
    else
      redirect_to backups_path, alert: restore.errors.full_messages.to_sentence
    end
  end
end
