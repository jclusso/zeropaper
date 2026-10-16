class Setup::AIChoicesController < ApplicationController
  include SetupStep

  def show
    @provider = AIProvider.order(:created_at).last || AIProvider.new(kind: "openai")
  end

  def update
    if params[:use_ai] == "0"
      @setting.update!(ai_enabled: false)
      return redirect_to setup_ocr_path
    end

    @provider = provider_for_update
    check = @provider.verify if @provider.save
    if @provider.persisted? && check&.ok?
      assign_default_models(@provider)
      redirect_to setup_models_path
    else
      @provider.errors.add(:base, check.message) if check && !check.ok?
      render :show, status: :unprocessable_entity
    end
  end

  private
    # Reuses the provider from an earlier pass through this step, so going
    # back and forth does not pile up providers.
    def provider_for_update
      attributes = provider_params
      provider = AIProvider.find_by(id: params[:provider_id]) || AIProvider.new
      attributes.delete(:api_key) if attributes[:api_key].blank? && provider.persisted? && provider.kind == attributes[:kind]
      provider.assign_attributes(attributes)
      provider
    end

    def provider_params
      params.expect(ai_provider: %i[ kind name api_key base_url ])
    end

    def assign_default_models(provider)
      attributes = { ai_enabled: true }
      Setting::TASKS.each_key do |task|
        current = @setting.provider_for(task)
        next if current && current != provider && @setting.model_for(task).present?

        attributes[:"#{task}_provider_id"] = provider.id
        attributes[:"#{task}_model"] = @setting.model_for(task).presence_in(provider.model_options(task)) || provider.default_model(task)
      end
      @setting.update!(attributes)
    end
end
