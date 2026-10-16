module AIProvidersHelper
  LOCAL_OCR_DESCRIPTIONS = {
    "tesseract" => "Runs in the app container. Fast, good on clean printed scans, and makes scans searchable in the viewer.",
    "docling" => "Runs in the docling container next to the app. Better with tables and complex layouts, slower on CPU."
  }.freeze


  TASK_DESCRIPTIONS = {
    "vision" => "Reads scans and photos. Also checks unclear blank pages when that is on."
  }.freeze

  def active_ocr_note(setting)
    if setting.task_configured?(:vision)
      safe_join([ private_badge, " documents and anything the model can't read use the fallback engine." ])
    else
      "Turn on Use AI and choose an OCR model under AI tasks to let AI read scans."
    end
  end

  def fallback_explanation
    "Runs on this machine. Reads private documents, every scan while AI is off or no OCR model is chosen, and any page the OCR model cannot read."
  end

  def provider_kind_options
    AIProvider::KINDS.map { |kind, spec| [ spec[:label], kind ] }
  end

  def provider_options
    AIProvider.alphabetically.map { |provider| [ provider.name == provider.label ? provider.name : "#{provider.name} (#{provider.label})", provider.id ] }
  end

  # Requirements per kind for the provider form's Stimulus controller.
  def provider_kind_requirements
    AIProvider::KINDS.transform_values { |spec| spec.slice(:key, :base_url) }.to_json
  end

  # API keys are typed into a text field masked with CSS, so browsers and
  # password managers do not offer to generate or save a password for them.
  def api_key_field(form, provider)
    saved = provider.persisted? && provider.api_key.present?
    form.text_field :api_key, value: nil, class: "input font-mono [-webkit-text-security:disc]",
      autocomplete: "off", spellcheck: false, autocapitalize: "off",
      placeholder: saved ? "saved, leave blank to keep it" : "paste the api key",
      data: { "1p-ignore": true, lpignore: "true", bwignore: true, form_type: "other" }
  end

  # Provider choices for a task row. Scans can be left to the local engine.
  def task_provider_options(task)
    task.to_s == "vision" ? [ [ "None (use the fallback engine)", "" ], *provider_options ] : provider_options
  end
end
