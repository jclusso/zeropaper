class Setup::ModelsController < ApplicationController
  include SetupStep

  before_action :require_ai

  def show
  end

  def update
    if @setting.update(task_params)
      redirect_to setup_ocr_path
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def require_ai
      redirect_to setup_ai_choice_path unless @setting.ai_enabled? && AIProvider.exists?
    end

    def task_params
      params.expect(setting: Setting::TASKS.keys.flat_map { |task| [ :"#{task}_provider_id", :"#{task}_model" ] })
    end
end
