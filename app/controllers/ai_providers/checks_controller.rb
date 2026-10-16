class AIProviders::ChecksController < ApplicationController
  require_admin

  def create
    provider = AIProvider.find(params[:ai_provider_id])
    check = provider.verify
    redirect_to settings_path(anchor: "ai"), (check.ok? ? :notice : :alert) => check.message
  end
end
