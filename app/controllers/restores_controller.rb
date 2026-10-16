class RestoresController < ApplicationController
  layout "admin"

  require_admin

  def new
    @restores = Restore.recent.limit(10)
  end

  def create
    archive = params[:archive]
    return redirect_to(new_restore_path, alert: "Choose a ZeroPaper export (.zip).") unless archive.respond_to?(:read)

    restore = Restore.new(user: Current.user)
    restore.archive.attach(archive)
    restore.save!
    restore.process_later
    redirect_to restore
  end

  def show
    @restore = Restore.find(params[:id])
  end
end
