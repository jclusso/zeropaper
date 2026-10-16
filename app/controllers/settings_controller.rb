class SettingsController < ApplicationController
  layout "admin"

  require_admin

  def show
    @setting = Setting.instance
  end

  def update
    @setting = Setting.instance
    if @setting.update(setting_params)
      redirect_to settings_path(anchor: params[:section]), notice: "Settings saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    AI_FIELDS = [ *Setting::TASKS.keys.flat_map { |task| [ :"#{task}_provider_id", :"#{task}_model" ] }, :blank_page_ai_check, :ai_creates_types, :ai_creates_tags ].freeze

    # With Use AI off the AI fields are locked in the form; any that arrive
    # anyway are ignored so the saved choices are there when AI comes back.
    def setting_params
      permitted = params.expect(setting: [
        :ai_enabled, *AI_FIELDS,
        :local_ocr_provider, :docling_url, :searchable_pdf,
        :auto_rotate_pages, :ingest_enabled, :ingest_dir, :blank_page_detection, :always_require_review, :review_confidence_threshold
      ])
      ai_on = permitted.key?(:ai_enabled) ? ActiveModel::Type::Boolean.new.cast(permitted[:ai_enabled]) : Setting.instance.ai_enabled?
      ai_on ? permitted : permitted.except(*AI_FIELDS)
    end
end
