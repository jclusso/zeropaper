# Asks the extraction model for a document's details. Goes through Outbound,
# so it refuses private documents, and offers the model only taxonomy names
# that are already used by non-private documents.
module Metadata
  class AI
    MAX_CHARACTERS = 24_000

    SCHEMA = {
      type: "object",
      properties: {
        title: { type: "string", description: "What the document is plus its key identifier, without the date, e.g. 'Electricity Bill', 'BMW X5 M Service Invoice', '2025 Tax Return'" },
        document_date: { type: [ "string", "null" ], description: "Date the document was issued, YYYY-MM-DD" },
        correspondent: { type: [ "string", "null" ], description: "Organization or person who sent or issued it" },
        document_type: { type: [ "string", "null" ], description: "Kind of document, e.g. Invoice, Receipt, Contract, Letter" },
        tags: { type: "array", items: { type: "string" }, description: "Up to 5 short topical tags" },
        summary: { type: "string", description: "Two or three sentences with the key facts: amounts, dates, reference numbers, what it asks of the reader" },
        confidence: { type: "number", description: "0 to 1, how sure you are of title, date, correspondent and type together" }
      },
      required: %w[title document_date correspondent document_type tags summary confidence],
      additionalProperties: false
    }.freeze

    def initialize(document)
      @document = document
      @settings = document.settings
      @overwrite = document.metadata_source != "manual"
    end

    def apply
      response = Outbound.for(@document)
        .chat(:extraction)
        .with_instructions(instructions)
        .with_schema(SCHEMA)
        .ask(prompt)
      details = response.parsed

      assign(:document_date, parse_date(details["document_date"]))
      assign(:title, DocumentTitle.clean(details["title"], date: @document.document_date))
      assign(:correspondent, Correspondent.find_or_create_named(details["correspondent"]))
      assign(:document_type, existing_or_new(DocumentType, details["document_type"], create: @settings.ai_creates_types?))
      if @overwrite || @document.tags.empty?
        names = Array(details["tags"]).first(5)
        names = names.filter_map { |name| Tag.named(name)&.name } unless @settings.ai_creates_tags?
        @document.tags = names.uniq(&:downcase).filter_map { |name| existing_or_new(Tag, name, create: true) }
      end
      Metadata::Rules.file(@document, text: text, overwrite: @overwrite)
      @document.summary = details["summary"].to_s.strip.presence
      @document.confidence = details["confidence"].to_f.clamp(0, 1)
      @document.ai_model = response.model || @settings.model_for(:extraction)
      @document.metadata_source = "ai" if @overwrite
      @document.save!
    end

    private
      def instructions
        <<~TEXT
          You file documents for a personal archive. Read the document and return its details.
          Reuse an existing name from the lists below when one fits, spelled exactly as listed.
          #{creation_rule}

          Titles: name what the document is and the detail that tells it apart (vehicle, account,
          service, tax year). Leave out the date, the correspondent's full name when it adds nothing,
          file names and reference numbers. Use Title Case. Name documents of the same kind the
          way the existing titles below do, so similar documents get the same title.
          Today is #{Date.current.iso8601}.
        TEXT
      end

      def prompt
        <<~TEXT
          Existing correspondents: #{names(Correspondent)}
          Existing document types: #{names(DocumentType)}
          Existing tags: #{names(Tag)}
          Existing titles: #{example_titles}

          Filename: #{@document.original_filename}

          Document text:
          #{text.first(MAX_CHARACTERS)}
        TEXT
      end

      def text
        @document.content.to_s.tr(Document::PAGE_BREAK, "\n")
      end

      def creation_rule
        fixed = [ ("document type" unless @settings.ai_creates_types?), ("tags" unless @settings.ai_creates_tags?) ].compact
        return "Only invent a new correspondent, type or tag when none fits." if fixed.empty?

        "Only invent a new correspondent when none fits. The #{fixed.to_sentence} must come from the lists; " \
          "use null or an empty list when nothing listed fits."
      end

      def existing_or_new(model, name, create:)
        # A type or tag the AI invents starts without auto-match: a word it
        # picked for one document ("Insurance") would otherwise land on every
        # document that mentions it.
        create ? model.find_or_create_named(name, auto_match: false) : model.named(name)
      end

      # Recent titles of non-private documents, as a naming style to follow.
      def example_titles
        Document.shareable.where(metadata_source: %w[ai manual]).where.not(id: @document.id).where.not(title: nil)
          .order(updated_at: :desc).limit(40).pluck(:title).uniq.join("; ").presence || "(none yet)"
      end

      def names(model)
        model.shareable.alphabetically.limit(300).pluck(:name).join("; ").presence || "(none yet)"
      end

      def assign(attribute, value)
        return if value.nil?
        return unless @overwrite || @document.public_send(attribute).blank?

        @document.public_send("#{attribute}=", value)
      end

      def parse_date(value)
        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end
  end
end
