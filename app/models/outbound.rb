# The only way ZeroPaper talks to an AI provider. Every call names the
# documents whose file, text or details it carries, and a private document is
# refused here. Privacy is read from the database, not from the objects passed
# in, and read again immediately before every request: each chat turn, each
# retry RubyLLM makes, and each OCR call. A document made private while a job
# runs stops that job's next request. The provider and model come from the
# task's assignment in Settings.
#
# A request that gets no answer within REQUEST_TIMEOUT fails and RubyLLM
# retries it, instead of waiting out its five minute default. Each retry is
# logged with how long the attempt before it ran.
#
#   Outbound.for(document).chat(:extraction).ask(...)
#   Outbound.for(document).ocr(path)              # an OCR model, e.g. Mistral's
#   Outbound.without_documents.chat(:research)    # e.g. Research
class Outbound
  class Error < StandardError; end
  class PrivateDocumentError < Error
    # The ids of the refused documents, nil for an unsaved one.
    attr_reader :document_ids

    def initialize(message = nil, document_ids: [])
      super(message)
      @document_ids = document_ids
    end
  end
  class NotConfiguredError < Error; end

  REQUEST_TIMEOUT = 2.minutes

  attr_reader :documents

  def self.for(*documents)
    documents = documents.flatten
    raise ArgumentError, "Outbound.for needs the documents a request carries; use Outbound.without_documents for none" if documents.empty?

    new(documents)
  end

  def self.without_documents
    new([])
  end

  # Checks documents a running chat is about to hand the model, such as a
  # research tool's results.
  def self.release!(documents)
    new(Array(documents)).documents
  end

  def initialize(documents)
    @documents = []
    release!(documents)
  end

  # Adds documents to what this outbound carries, so every later request of
  # its chats checks them too. Returns the documents.
  def release!(documents)
    documents = Array(documents)
    raise ArgumentError, "Outbound was given nil for a document" if documents.any?(&:nil?)

    @documents |= documents
    authorize!
    documents
  end

  # Raises unless every document is saved and still not private in the
  # database. Unsaved or deleted documents are refused as well. Bypasses the
  # query cache, which jobs run with, so another process's change is seen.
  def authorize!
    return if documents.empty?

    shareable = Document.uncached { Document.shareable.where(id: documents.filter_map(&:id)).pluck(:id).to_set }
    refused = documents.reject { |document| !document.private? && shareable.include?(document.id) }
    return if refused.empty?

    ids = refused.map(&:id)
    raise PrivateDocumentError.new("Private documents never leave this machine (#{ids.map { |id| id || "unsaved" }.join(", ")})", document_ids: ids)
  end

  # A longer timeout suits requests that take longer by nature, such as
  # reading many pages.
  def chat(task, timeout: REQUEST_TIMEOUT)
    settings = Setting.instance
    unless settings.task_configured?(task)
      raise NotConfiguredError, "Choose a provider and model for “#{Setting::TASKS.fetch(task.to_s)}” under AI tasks in Settings to use this."
    end

    authorize!
    settings.provider_for(task).chat(model: settings.model_for(task), timeout: timeout).tap { |chat| authorize_every_request(chat.provider.connection, task) }
  end

  # Reads a file with a dedicated OCR model, such as Mistral Document OCR.
  def ocr(path, timeout: REQUEST_TIMEOUT)
    settings = Setting.instance
    raise NotConfiguredError, "Choose an OCR model under AI tasks in Settings to read scans with AI." unless settings.task_configured?(:vision)

    authorize!
    settings.provider_for(:vision).ocr(path, model: settings.model_for(:vision), timeout: timeout) { |provider| authorize_every_request(provider.connection, :vision) }
  end

  # The provider and model a task would use, for labels and records.
  def self.model_label(task)
    settings = Setting.instance
    [ settings.provider_for(task)&.name, settings.model_for(task) ].compact.join(" · ")
  end

  private
    # RubyLLM calls a connection's signer on every transport attempt, inside
    # its retry middleware, right before the request is sent. Wrapping it
    # runs authorize! for each turn of a tool-calling chat and for each
    # retry, OCR uploads included. Each chat and OCR call has its own
    # provider and connection, so this never touches another call's
    # requests. Refuses to send through a connection it cannot check.
    #
    # The retry middleware sends the same env again, which is how a retry is
    # told apart from the next turn of a chat.
    def authorize_every_request(connection, task)
      raise Error, "Cannot check this provider's requests for privacy" unless connection.instance_variable_defined?(:@signer)

      signer = connection.instance_variable_get(:@signer)
      attempts = {}.compare_by_identity
      connection.instance_variable_set(:@signer, ->(env) {
        authorize!
        log_retry(task, attempts, env)
        signer ? signer.call(env) : {}
      })
    end

    def log_retry(task, attempts, env)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      count, started = attempts[env]
      attempts[env] = [ count.to_i + 1, now ]
      return unless started

      Rails.logger.warn("[outbound] #{task} request retried (attempt #{count + 1}) after the last one ran #{(now - started).round(1)}s")
    end
end
