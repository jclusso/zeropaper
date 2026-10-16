class Documents::PrivaciesController < ApplicationController
  include DocumentScoped

  def create
    @document.privatize!(reason: "Marked private by #{Current.user.name}")
    redirect_to @document, notice: "Marked private. It will be processed again locally."
  end

  def destroy
    @document.publicize!
    redirect_to @document, notice: "No longer private. It will be processed again with AI.", status: :see_other
  end
end
