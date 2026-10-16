# Fills in a document's details without AI: correspondent, type and tags by
# name and by Rules, the date by finding dates in the text, and a title from
# the first meaningful line or the filename. Private documents always get
# their details this way.
module Metadata
  class Rules
    MONTH_PATTERN = (Date::MONTHNAMES.compact + Date::ABBR_MONTHNAMES.compact).uniq.join("|")
    DATE_PATTERNS = [
      /\b(?<year>(?:19|20)\d{2})-(?<month>\d{1,2})-(?<day>\d{1,2})\b/,
      /\b(?<month>\d{1,2})\/(?<day>\d{1,2})\/(?<year>(?:19|20)\d{2})\b/,
      /\b(?<day>\d{1,2})\.(?<month>\d{1,2})\.(?<year>(?:19|20)\d{2})\b/,
      /\b(?<month_name>#{MONTH_PATTERN})\.? (?<day>\d{1,2})(?:st|nd|rd|th)?,? (?<year>(?:19|20)\d{2})\b/i,
      /\b(?<day>\d{1,2})(?:st|nd|rd|th)? (?<month_name>#{MONTH_PATTERN})\.?,? (?<year>(?:19|20)\d{2})\b/i
    ].freeze
    SCANNER_FILENAME = /\A(?:scan|scanned|img|image|doc|document|page|untitled)?[\s_-]*[\d\s_-]*\z/i

    def initialize(document)
      @document = document
      @text = document.content.to_s.tr(Document::PAGE_BREAK, "\n")
      @overwrite = document.metadata_source != "manual"
    end

    def apply
      assign(:correspondent, Correspondent.mentioned_in(@text).first)
      assign(:document_type, DocumentType.mentioned_in(@text).first)
      Metadata::Rules.file(@document, text: @text, overwrite: @overwrite)
      assign(:document_date, find_date)
      assign(:title, DocumentTitle.clean(find_title, date: @document.document_date))

      @document.metadata_source = "rules" if @overwrite
      @document.confidence = nil
      @document.save!
    end

    # Adds tags whose names appear in the text and applies matching Rules,
    # which win over anything found by name or suggested by AI.
    def self.file(document, text:, overwrite:)
      mentioned = Tag.mentioned_in(text)
      document.tags = (document.tags.to_a + mentioned).uniq if mentioned.any?
      Rule.matching(document, text: text).each { |rule| rule.apply_filing(document, overwrite: overwrite) }
    end

    # The earliest date in the text that is plausible for a document.
    def find_date
      latest_plausible = Date.current + 1.year
      sample = @text.first(20_000)
      found = DATE_PATTERNS.flat_map do |pattern|
        sample.to_enum(:scan, pattern).map { Regexp.last_match }.filter_map do |match|
          date = parse_date(match)
          [ match.begin(0), date ] if date && date.year >= 1900 && date <= latest_plausible
        end
      end
      found.min_by(&:first)&.last
    end

    def find_title
      name = File.basename(@document.original_filename, ".*")
      return name.tr("_", " ").squish.truncate(120) unless name.match?(SCANNER_FILENAME)

      line = @text.lines.map(&:squish).find { |candidate| candidate.length.between?(8, 120) && candidate.count("a-zA-Z") > candidate.length / 2 }
      [ line, @document.correspondent&.name, @document.document_type&.name ].compact.first || name
    end

    private
      def assign(attribute, value)
        return if value.nil?
        return unless @overwrite || @document.public_send(attribute).blank?

        @document.public_send("#{attribute}=", value)
      end

      def parse_date(match)
        month = match.names.include?("month_name") ? month_number(match[:month_name]) : match[:month].to_i
        Date.new(match[:year].to_i, month, match[:day].to_i)
      rescue Date::Error, TypeError
        nil
      end

      def month_number(name)
        name = name.downcase.delete(".")
        Date::MONTHNAMES.index { |month| month&.downcase == name } || Date::ABBR_MONTHNAMES.index { |month| month&.downcase == name }
      end
  end
end
