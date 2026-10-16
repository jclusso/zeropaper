class Setup::OcrsController < ApplicationController
  include SetupStep

  def show
  end

  def update
    if @setting.update(ocr_params)
      @setting.complete_setup!
      redirect_to root_path, notice: "ZeroPaper is ready. Upload your first documents to get started."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def ocr_params
      params.expect(setting: %i[ local_ocr_provider docling_url ])
    end
end
