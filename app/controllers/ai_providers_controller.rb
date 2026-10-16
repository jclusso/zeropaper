class AIProvidersController < ApplicationController
  layout "admin"

  require_admin
  before_action :set_provider, only: %i[ edit update destroy ]

  def new
    @provider = AIProvider.new(kind: params[:kind].presence_in(AIProvider::KINDS.keys) || "openai")
  end

  def create
    @provider = AIProvider.new(provider_params)
    if @provider.save
      redirect_to settings_path(anchor: "ai"), notice: "#{@provider.name} added. Test it, then assign it to tasks below."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attributes = provider_params
    attributes.delete(:api_key) if attributes[:api_key].blank?
    if @provider.update(attributes)
      redirect_to settings_path(anchor: "ai"), notice: "#{@provider.name} saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @provider.destroy
    redirect_to settings_path(anchor: "ai"), notice: "#{@provider.name} removed. Tasks that used it need another provider."
  end

  private
    def set_provider
      @provider = AIProvider.find(params[:id])
    end

    def provider_params
      params.expect(ai_provider: %i[ kind name api_key base_url ])
    end
end
