# Stopping a run in progress. The running step finishes, then the run gives
# up; anything still queued is discarded.
class Documents::ProcessingsController < ApplicationController
  include DocumentScoped

  def destroy
    @document.stop_processing!
    redirect_to @document, notice: "Processing stopped. Retry when you are ready."
  end
end
