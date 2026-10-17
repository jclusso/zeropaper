# A hosted or local AI service ZeroPaper can call through RubyLLM. Settings
# assign one provider and model to each task (document details, research,
# vision). Every call still goes through Outbound, so private documents never
# reach any provider.
class AIProvider < ApplicationRecord
  KINDS = {
    "openai" => { label: "OpenAI", key: :required, base_url: :optional },
    "anthropic" => { label: "Anthropic", key: :required, base_url: :optional },
    "gemini" => { label: "Google Gemini", key: :required, base_url: :optional },
    "mistral" => { label: "Mistral", key: :required, base_url: :optional },
    "openrouter" => { label: "OpenRouter", key: :required, base_url: :optional },
    "deepseek" => { label: "DeepSeek", key: :required, base_url: :optional },
    "xai" => { label: "xAI", key: :required, base_url: :optional },
    "ollama" => { label: "Ollama", key: :optional, base_url: :required },
    "openai_compatible" => { label: "OpenAI-compatible API", key: :optional, base_url: :required }
  }.freeze

  # Sensible starting models per task, used to prefill Settings.
  DEFAULT_MODELS = {
    "openai" => { "extraction" => "gpt-5.6-luna", "research" => "gpt-5.6", "vision" => "gpt-5.6-luna" },
    "anthropic" => { "extraction" => "claude-haiku-4-5", "research" => "claude-sonnet-4-5", "vision" => "claude-haiku-4-5" },
    "gemini" => { "extraction" => "gemini-2.5-flash", "research" => "gemini-2.5-pro", "vision" => "gemini-2.5-flash" },
    "mistral" => { "extraction" => "mistral-small-latest", "research" => "mistral-large-latest", "vision" => "mistral-ocr-latest" }
  }.freeze

  LIVE_MODEL_LISTS = %w[ollama openai_compatible].freeze

  Check = Struct.new(:ok, :message) do
    def ok? = ok
  end

  encrypts :api_key

  has_many :extraction_settings, class_name: "Setting", foreign_key: :extraction_provider_id, dependent: :nullify, inverse_of: :extraction_provider
  has_many :research_settings, class_name: "Setting", foreign_key: :research_provider_id, dependent: :nullify, inverse_of: :research_provider
  has_many :vision_settings, class_name: "Setting", foreign_key: :vision_provider_id, dependent: :nullify, inverse_of: :vision_provider

  normalizes :base_url, with: ->(url) { url.strip.chomp("/").presence }
  normalizes :api_key, with: ->(key) { key.strip.presence }

  validates :kind, inclusion: { in: KINDS.keys }
  validates :name, presence: true
  validates :api_key, presence: { message: "is required for this provider" }, if: -> { spec[:key] == :required }
  validates :base_url, presence: { message: "is required for this provider" }, if: -> { spec[:base_url] == :required }
  validates :base_url, format: { with: %r{\Ahttps?://\S+\z}, message: "must start with http:// or https://" }, allow_nil: true

  before_validation -> { self.name = label if name.blank? && kind.in?(KINDS.keys) }

  scope :alphabetically, -> { order(:name) }

  def label
    KINDS.dig(kind, :label) || kind.to_s.humanize
  end

  def spec
    KINDS.fetch(kind, {})
  end

  # Dedicated OCR models are read through RubyLLM's OCR API instead of chat.
  def ocr_model?(model)
    model.to_s.match?(/(\A|[-_])ocr([-_]|\z)/)
  end

  def default_model(task)
    preferred = DEFAULT_MODELS.dig(kind, task.to_s)
    return preferred if preferred && (model_options(task).empty? || model_options(task).include?(preferred))

    model_options(task).first
  end

  # Model ids that fit a task: any chat model for details and research,
  # models that take images or PDFs for vision. Hosted providers come from
  # RubyLLM's registry; Ollama and OpenAI-compatible servers are asked.
  def model_options(task)
    @model_options ||= {}
    @model_options[task.to_s] ||=
      if kind.in?(LIVE_MODEL_LISTS)
        live_models
      else
        registry_models(task)
      end
  end

  # RubyLLM's name for the provider. OpenAI-compatible servers speak OpenAI.
  def ruby_llm_provider
    kind == "openai_compatible" ? :openai : kind.to_sym
  end

  # A RubyLLM context holding only this provider's credentials.
  def context
    RubyLLM.context do |config|
      config.public_send("#{ruby_llm_provider}_api_key=", api_key) if api_key.present? || ruby_llm_provider != :ollama
      config.public_send("#{ruby_llm_provider}_api_base=", api_base) if api_base
    end
  end

  def chat(model:)
    context.chat(model: model, provider: ruby_llm_provider, assume_model_exists: !registry_knows?(model))
  end

  # Builds the RubyLLM provider for this one call and yields it before the
  # file is sent, so Outbound can check every request it makes. Needs the
  # block, so a call that skips the check fails before anything is sent.
  def ocr(path, model:)
    model, provider = RubyLLM::Models.resolve(model, provider: ruby_llm_provider, assume_model_exists: !registry_knows?(model), config: context.config)
    yield provider
    provider.ocr(path, model: model)
  end

  # Confirms the key and address work by listing models, which costs nothing.
  def verify
    response = HttpRequest.get(models_url, headers: auth_headers, read_timeout: 15)
    if response.is_a?(HTTPX::ErrorResponse)
      Check.new(false, "Could not reach #{label}: #{response.error.message}")
    elsif response.status == 401 || response.status == 403
      Check.new(false, "#{label} rejected the API key.")
    elsif response.status >= 400
      Check.new(false, "#{label} answered #{response.status}.")
    else
      Check.new(true, "Connected to #{label}.")
    end
  rescue StandardError => error
    Check.new(false, "Could not reach #{label}: #{error.message.truncate(120)}")
  end

  private
    def registry_models(task)
      models = RubyLLM.models.by_provider(ruby_llm_provider).chat_models.reject(&:unlisted?)
      ids = models.map(&:id)
      if task.to_s == "vision"
        ids = models.select { |model| (Array(model.modalities&.input) & %w[image pdf]).any? }.map(&:id)
        ids += RubyLLM.models.by_provider(ruby_llm_provider).all.map(&:id).select { |id| ocr_model?(id) }
      end
      ids.uniq.sort
    rescue StandardError
      []
    end

    def registry_knows?(model)
      return false if kind.in?(LIVE_MODEL_LISTS)

      RubyLLM.models.by_provider(ruby_llm_provider).all.any? { |known| known.id == model }
    rescue StandardError
      false
    end

    def live_models
      Rails.cache.fetch([ "ai_provider_models", id, base_url, updated_at.to_i ], expires_in: 10.minutes) do
        response = HttpRequest.get(models_url, headers: auth_headers, read_timeout: 10)
        next [] unless response.is_a?(HTTPX::Response) && response.status == 200

        body = response.json
        ids = kind == "ollama" ? Array(body["models"]).map { |model| model["name"] } : Array(body["data"]).map { |model| model["id"] }
        ids.compact.sort
      end
    rescue StandardError
      []
    end

    def api_base
      base_url if base_url.present?
    end

    def models_url
      case kind
      when "anthropic" then "#{base_url || "https://api.anthropic.com"}/v1/models"
      when "gemini" then "#{base_url || "https://generativelanguage.googleapis.com"}/v1beta/models"
      when "mistral" then "#{base_url || "https://api.mistral.ai"}/v1/models"
      when "openrouter" then "#{base_url || "https://openrouter.ai/api/v1"}/key"
      when "deepseek" then "#{base_url || "https://api.deepseek.com"}/models"
      when "xai" then "#{base_url || "https://api.x.ai"}/v1/models"
      when "ollama" then "#{base_url}/api/tags"
      when "openai_compatible" then "#{base_url}/models"
      else "#{base_url || "https://api.openai.com/v1"}/models"
      end
    end

    def auth_headers
      return {} if api_key.blank?

      case kind
      when "anthropic" then { "x-api-key" => api_key, "anthropic-version" => "2023-06-01" }
      when "gemini" then { "x-goog-api-key" => api_key }
      else { "authorization" => "Bearer #{api_key}" }
      end
    end
end
