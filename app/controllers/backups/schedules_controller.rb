class Backups::SchedulesController < ApplicationController
  require_admin

  def update
    setting = Setting.instance
    if setting.update(schedule_params)
      redirect_to backups_path, notice: "Backup schedule saved."
    else
      redirect_to backups_path, alert: setting.errors.full_messages.to_sentence
    end
  end

  private
    def schedule_params
      params.expect(setting: %i[ backup_enabled backup_frequency backup_keep_daily backup_keep_weekly backup_keep_monthly backup_keep_yearly ])
    end
end
