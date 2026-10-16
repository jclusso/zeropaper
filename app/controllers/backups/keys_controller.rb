class Backups::KeysController < ApplicationController
  require_admin

  def show
    setting = Setting.instance
    contents = Backup::Key.file_contents(Backup::Key.encode(setting.backup_key_bytes))
    setting.update!(backup_key_downloaded_at: Time.current)

    response.headers["Cache-Control"] = "private, no-store"
    send_data contents, filename: "zeropaper-backup-key-#{setting.backup_key_id}.txt", type: "text/plain", disposition: :attachment
  end
end
