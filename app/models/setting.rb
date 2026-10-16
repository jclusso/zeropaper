class Setting < ApplicationRecord
  LOCAL_OCR_PROVIDERS = {
    "tesseract" => "Tesseract (local)",
    "docling" => "Docling (local)"
  }.freeze

  TASKS = {
    "extraction" => "Document details",
    "research" => "Research",
    "vision" => "OCR"
  }.freeze

  belongs_to :extraction_provider, class_name: "AIProvider", optional: true
  belongs_to :research_provider, class_name: "AIProvider", optional: true
  belongs_to :vision_provider, class_name: "AIProvider", optional: true

  encrypts :backup_key

  validates :local_ocr_provider, inclusion: { in: LOCAL_OCR_PROVIDERS.keys }
  validates :review_confidence_threshold, numericality: { in: 0..1 }
  validates :docling_url, presence: true, if: -> { local_ocr_provider == "docling" }
  # The first save takes DOCLING_URL, which from_environment already
  # checked; its host may not resolve until the container starts.
  validate :docling_url_is_local, on: :update, if: -> { docling_url.present? && docling_url_changed? }
  validate :tasks_have_models
  validates :backup_frequency, inclusion: { in: Backup::FREQUENCIES.keys }
  validates :backup_keep_daily, :backup_keep_weekly, :backup_keep_monthly, :backup_keep_yearly, numericality: { only_integer: true, in: 0..1000 }

  def self.instance
    first || create!(from_environment)
  end

  # DOCLING_URL is ignored when it points elsewhere. A host that does not
  # resolve yet is kept: whether Docling is local is decided again for each
  # document, which is read with Tesseract while it is not.
  def self.from_environment
    docling_url = ENV["DOCLING_URL"].presence
    if docling_url && LocalNetwork.elsewhere?(docling_url)
      Rails.logger.warn("[settings] ignoring DOCLING_URL #{docling_url}: Docling must run on this machine or the local network")
      docling_url = nil
    end

    { docling_url: docling_url, local_ocr_provider: docling_url ? "docling" : "tesseract" }.compact
  end

  def provider_for(task)
    public_send("#{task}_provider") if task.to_s.in?(TASKS.keys)
  end

  def model_for(task)
    public_send("#{task}_model").presence if task.to_s.in?(TASKS.keys)
  end

  def task_configured?(task)
    ai_enabled? && provider_for(task).present? && model_for(task).present?
  end

  # Document details are the core AI feature; without them ZeroPaper files
  # documents with local rules only.
  def ai_configured?
    task_configured?(:extraction)
  end

  def local_ocr_options
    docling_url.present? ? LOCAL_OCR_PROVIDERS.keys : %w[tesseract]
  end

  def local_ocr_label
    LOCAL_OCR_PROVIDERS.fetch(local_ocr_provider)
  end

  # The local engine that reads documents. Docling only counts as local
  # while its address is on this machine or the local network, checked again
  # now because a name can resolve elsewhere later; when it is not, every
  # document is read with Tesseract, since local reads include the privacy
  # screen of shareable documents. Docling checks again before each request.
  def local_ocr_engine
    return "tesseract" if local_ocr_provider == "docling" && !docling_local?

    local_ocr_provider
  end

  def docling_local?
    LocalNetwork.url?(docling_url)
  end

  # Scans are read by the OCR model when AI is on and one is chosen. The
  # local engine reads private documents and is the fallback for everything
  # else, including when the OCR model fails.
  def ai_reads_scans_for?(document)
    !document.private? && task_configured?(:vision)
  end

  # What reads scans right now: the OCR model, or the local engine when AI
  # is off or no OCR model is chosen.
  def active_ocr_label
    task_configured?(:vision) ? Outbound.model_label(:vision) : local_ocr_label
  end

  # The watched folder, INGEST_DIR. Docker installs choose where it lives by
  # what they mount there.
  def ingest_path
    Rails.configuration.x.ingest_dir
  end

  def private_ingest_path
    File.join(ingest_path, Ingest::Folder::PRIVATE_DIR)
  end

  # The raw backup key, made the first time it is needed. The lock keeps two
  # processes from each making one and encrypting a backup with the loser.
  def backup_key_bytes
    with_lock { update!(backup_key: Backup::Key.generate) if backup_key.blank? } if backup_key.blank?
    Backup::Key.parse(backup_key)
  end

  def backup_key_id
    Backup::Key.id(backup_key_bytes)
  end

  def backup_interval
    Backup::FREQUENCIES.fetch(backup_frequency)
  end

  def setup_complete?
    setup_completed_at.present?
  end

  def complete_setup!
    update!(setup_completed_at: Time.current)
  end

  private
    def docling_url_is_local
      errors.add(:docling_url, "must be on this machine or the local network, such as http://zeropaper-docling:5001") unless docling_local?
    end

    def tasks_have_models
      TASKS.each_key do |task|
        next unless provider_for(task)

        errors.add(:"#{task}_model", "is required when a provider is chosen") if model_for(task).blank?
      end
    end
end
