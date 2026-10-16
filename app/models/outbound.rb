# The only way ZeroPaper talks to an AI provider. Every call names the
# documents whose file, text or details it carries, and a private document is
# refused here, before any request is built. The provider and model come from
# the task's assignment in Settings.
#
#   Outbound.for(document).chat(:extraction).ask(...)
#   Outbound.for(document).ocr(path)              # an OCR model, e.g. Mistral's
#   Outbound.without_documents.chat(:research)    # e.g. Research
class Outbound
  class Error < StandardError; end
  class PrivateDocumentError < Error; end
  class NotConfiguredError < Error; end

  attr_reader :documents

  def self.for(*documents)
    new(documents.flatten.compact)
  end

  def self.without_documents
    new([])
  end

  # Checks documents a running chat is about to hand the model, such as a
  # research tool's results.
  def self.release!(documents)
    new(Array(documents))
    documents
  end

  def initialize(documents)
    @documents = documents
    refused = documents.select(&:private?)
    raise PrivateDocumentError, "Private documents never leave this machine (#{refused.map(&:id).join(", ")})" if refused.any?
  end

  def chat(task)
    settings = Setting.instance
    unless settings.task_configured?(task)
      raise NotConfiguredError, "Choose a provider and model for “#{Setting::TASKS.fetch(task.to_s)}” under AI tasks in Settings to use this."
    end

    settings.provider_for(task).chat(model: settings.model_for(task))
  end

  # Reads a file with a dedicated OCR model, such as Mistral Document OCR.
  def ocr(path)
    settings = Setting.instance
    raise NotConfiguredError, "Choose an OCR model under AI tasks in Settings to read scans with AI." unless settings.task_configured?(:vision)

    settings.provider_for(:vision).ocr(path, model: settings.model_for(:vision))
  end

  # The provider and model a task would use, for labels and records.
  def self.model_label(task)
    settings = Setting.instance
    [ settings.provider_for(task)&.name, settings.model_for(task) ].compact.join(" · ")
  end
end
