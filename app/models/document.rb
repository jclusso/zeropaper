class Document < ApplicationRecord
  include Ingestible, Privacy, Pages, Processing, Searchable, Reviewable, Filterable

  STATUSES = %w[pending processing ready failed].freeze
  SOURCES = %w[upload folder restore].freeze
  SPREADSHEET_VIEW_ROWS = 2_000

  # Private documents are stored on the encrypted disk service.
  STORAGE = ->(document) { document.storage_service_name }

  belongs_to :correspondent, optional: true
  belongs_to :document_type, optional: true
  belongs_to :duplicate_of, class_name: "Document", optional: true
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_many :taggings, dependent: :delete_all
  has_many :tags, through: :taggings
  has_many :chunks, -> { order(:position) }, dependent: :delete_all

  has_one_attached :file, service: STORAGE
  has_one_attached :original_file, service: STORAGE
  has_one_attached :archive_file, service: STORAGE
  has_one_attached :thumbnail, service: STORAGE

  encrypts :content, :summary

  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :checksum, presence: true, uniqueness: true
  validates :original_filename, :content_type, presence: true

  scope :ready, -> { where(status: "ready") }
  scope :chronologically, -> { order(Arel.sql("coalesce(documents.document_date, documents.created_at::date) desc, documents.id desc")) }
  scope :recently_added, -> { order(created_at: :desc, id: :desc) }

  # Documents that looked like copies of this one are no longer duplicates.
  before_destroy :clear_duplicate_flags

  broadcasts_refreshes

  def display_title
    title.presence || File.basename(original_filename, ".*")
  end

  def display_date
    document_date || created_at.to_date
  end

  def pdf?
    content_type == "application/pdf"
  end

  def image?
    content_type.start_with?("image/")
  end

  def spreadsheet?
    content_type.in?(NativeText::SPREADSHEET_TYPES)
  end

  # Sheets for the viewer, parsed once per file rather than on every view.
  # Keyed by the blob, so a replaced file is parsed again.
  def spreadsheet_sheets
    return [] unless spreadsheet? && file.attached?

    json = SealedCache.fetch([ "spreadsheet-sheets", file.blob.key ], expires_in: 1.week) do
      sheets = file.open { |copy| NativeText.sheets(copy.path, content_type) }
      sheets.map { |sheet| sheet.merge(rows: sheet[:rows].first(SPREADSHEET_VIEW_ROWS)) }.to_json
    end
    JSON.parse(json, symbolize_names: true)
  rescue StandardError
    []
  end

  # What the viewer shows: the searchable PDF made by OCR when there is one,
  # so text is selectable and findable even on a scan.
  def viewable_pdf
    return archive_file if archive_file.attached?

    file if pdf?
  end

  # What Download gives: the searchable PDF when OCR made one, otherwise the
  # current file. Both have pages turned upright and removed pages gone.
  def best_download
    archive_file.attached? ? archive_file : file
  end

  # The file as uploaded, when it differs from the best download. Nil when
  # the best download is the upload itself.
  def original_download
    return original_file if original_file.attached?

    file if archive_file.attached?
  end

  def storage_service_name
    base = ActiveStorage::Blob.service.name.to_s
    private? ? "#{base}_private" : base
  end

  # Saves details edited by a person. They only become "from you" when a
  # field actually changed, so saving AI details untouched keeps their source
  # and confidence.
  def edit_details(attributes)
    attributes = attributes.to_h.symbolize_keys
    attributes[:title] = attributes[:title].presence if attributes.key?(:title)
    attributes[:summary] = attributes[:summary].presence if attributes.key?(:summary)
    attributes.delete(:title) if title.nil? && attributes[:title] == display_title
    # Assigning tags saves them at once, so compare names before touching them.
    if attributes.key?(:tag_names)
      same_tags = attributes[:tag_names].map(&:downcase).uniq.sort == tags.map { |current| current.name.downcase }.sort
      attributes.delete(:tag_names) if same_tags
    end

    tags_changed = attributes.key?(:tag_names)
    assign_attributes(attributes)
    self.metadata_source = "manual" if changed? || tags_changed
    return false unless save

    refresh_search_vector
    review_checked!
    true
  end

  def tag_names=(names)
    self.tags = Array(names).compact_blank.uniq { |name| name.downcase }.filter_map { |name| Tag.find_or_create_named(name) }
  end

  def settings
    @settings ||= Setting.instance
  end

  private
    def clear_duplicate_flags
      Document.where(duplicate_of_id: id).find_each do |copy|
        copy.update_columns(duplicate_of_id: nil)
        copy.review_resolved!("possible_duplicate")
      end
    end
end
