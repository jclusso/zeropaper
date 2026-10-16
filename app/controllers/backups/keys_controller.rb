class Backups::KeysController < ApplicationController
  require_admin

  def show
    setting = Setting.instance
    setting.update!(backup_key_downloaded_at: Time.current)

    response.headers["Cache-Control"] = "private, no-store"
    send_data "#{Backup::Key.encode(setting.backup_key_bytes)}\n", filename: "zeropaper.key", type: "application/octet-stream", disposition: :attachment
  end
end
