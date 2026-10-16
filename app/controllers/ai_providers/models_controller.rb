# The model picker for one task, reloaded into its frame when the task's
# provider changes.
class AIProviders::ModelsController < ApplicationController
  allow_before_setup
  require_admin

  def index
    @provider = AIProvider.find(params[:ai_provider_id])
    @task = params[:task].presence_in(Setting::TASKS.keys) or return head(:not_found)
    @value = @provider.default_model(@task)
  end
end
