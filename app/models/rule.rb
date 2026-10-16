# Automatic filing: when a document meets the conditions, set its
# correspondent and type, add tags, or mark it private. Rules run locally.
# Rules that only look at the filename or source run at ingest; the rest run
# once the text has been read on this machine, before anything that could
# send the document out.
class Rule < ApplicationRecord
  FIELDS = {
    "content" => "Document text",
    "filename" => "Filename",
    "source" => "Source"
  }.freeze

  OPERATORS = {
    "any" => "contains any of",
    "all" => "contains all of",
    "phrase" => "contains the phrase",
    "regex" => "matches the pattern",
    "is" => "is"
  }.freeze
  TEXT_OPERATORS = %w[any all phrase regex].freeze

  SOURCES = { "upload" => "Upload", "folder" => "Watched folder", "restore" => "Restore" }.freeze
  MATCH_MODES = { "all" => "All conditions", "any" => "Any condition" }.freeze

  belongs_to :correspondent, optional: true
  belongs_to :document_type, optional: true

  normalizes :conditions, with: ->(conditions) {
    Array(conditions).map { |condition| condition.to_h.stringify_keys.slice("field", "operator", "value") }
      .reject { |condition| condition["value"].blank? }
  }

  validates :name, presence: true
  validates :match_mode, inclusion: { in: MATCH_MODES.keys }
  validate :conditions_are_valid
  validate :has_an_action

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:position, :id) }

  def self.matching(document, text: nil)
    enabled.ordered.select { |rule| rule.matches?(document, text: text) }
  end

  # Rules that can decide before the text is read.
  def self.matching_before_content(document)
    enabled.ordered.reject(&:needs_content?).select { |rule| rule.matches?(document) }
  end

  # Marks documents that mention the correspondent private and files them
  # under it, which is what older exports' "documents from this correspondent
  # are private" setting meant. Skipped when an enabled rule already marks
  # private any text with that phrase, whatever its case, alone or as one of
  # several "any" conditions.
  def self.privatize_mentions_of!(correspondent)
    return if enabled.where(mark_private: true).any? { |rule| rule.privatizes_phrase?(correspondent.name) }

    phrase = { "field" => "content", "operator" => "phrase", "value" => correspondent.name }
    create!(name: "Private: #{correspondent.name}", conditions: [ phrase ], correspondent: correspondent, mark_private: true)
  end

  def privatizes_phrase?(name)
    phrase = conditions.any? do |condition|
      condition["field"] == "content" && condition["operator"] == "phrase" && condition["value"].to_s.squish.casecmp?(name.squish)
    end
    phrase && (conditions.size == 1 || match_mode == "any")
  end

  def tags
    Tag.where(id: tag_ids)
  end

  def needs_content?
    conditions.any? { |condition| condition["field"] == "content" }
  end

  def matches?(document, text: nil)
    return false if conditions.empty?

    results = conditions.map { |condition| condition_met?(condition, document, text) }
    match_mode == "any" ? results.any? : results.all?
  end

  # Applies the filing actions. Privacy is handled separately by the
  # pipeline, because it has to happen before anything else.
  def apply_filing(document, overwrite:)
    document.correspondent = correspondent if correspondent && (overwrite || document.correspondent.nil?)
    document.document_type = document_type if document_type && (overwrite || document.document_type.nil?)
    document.tags = (document.tags.to_a + tags.to_a).uniq if tag_ids.any?
  end

  def private_reason
    "Matched rule “#{name}”"
  end

  private
    def condition_met?(condition, document, text)
      value = condition["value"]
      subject =
        case condition["field"]
        when "content" then text || document.content.to_s.tr(Document::PAGE_BREAK, "\n")
        when "filename" then document.original_filename
        when "source" then document.source
        end

      case condition["operator"]
      when "any" then TextMatch.any?(subject, value)
      when "all" then TextMatch.all?(subject, value)
      when "phrase" then TextMatch.phrase?(subject, value)
      when "regex" then TextMatch.regex?(subject, value)
      when "is" then subject.to_s == value.to_s
      else false
      end
    end

    def conditions_are_valid
      errors.add(:conditions, "need at least one condition") if conditions.empty?
      conditions.each do |condition|
        unless condition["field"].in?(FIELDS.keys) && condition["operator"].in?(OPERATORS.keys)
          errors.add(:conditions, "include an unknown field or operator")
          next
        end
        if condition["field"] == "source" && !(condition["operator"] == "is" && condition["value"].in?(SOURCES.keys))
          errors.add(:conditions, "must compare the source with one of #{SOURCES.values.to_sentence}")
        end
        errors.add(:conditions, "can only use “is” for the source") if condition["operator"] == "is" && condition["field"] != "source"
        if condition["operator"] == "regex"
          begin
            Regexp.new(condition["value"].to_s)
          rescue RegexpError => error
            errors.add(:conditions, "have an invalid pattern (#{error.message})")
          end
        end
      end
    end

    def has_an_action
      return if correspondent || document_type || tag_ids.any? || mark_private?

      errors.add(:base, "Choose at least one thing for the rule to do")
    end
end
