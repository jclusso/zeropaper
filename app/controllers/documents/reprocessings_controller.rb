class Documents::ReprocessingsController < ApplicationController
  include DocumentScoped

  # Also restarts a run in progress: the old run sees it is no longer current
  # and stops at its next step.
  def create
    restarting = @document.processing?
    @document.process_later(extract_metadata: params[:metadata] != "0")
    redirect_to @document, notice: restarting ? "Restarted processing." : "Processing again."
  end
end
