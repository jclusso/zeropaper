# A second opinion for pages the local check cannot settle, where heavy
# bleed-through and faint print look alike. One request per document, each
# unclear page sent with the page before it. Off by default because it spends
# tokens, and never offered for private documents. It runs before the text is
# read, so it also waits while a content rule could still make the document
# private.
module BlankPages
  class Judge
    RENDER_EDGE = 1_000

    SCHEMA = {
      type: "object",
      properties: {
        pages: {
          type: "array",
          items: {
            type: "object",
            properties: { page: { type: "integer" }, blank: { type: "boolean" } },
            required: %w[page blank],
            additionalProperties: false
          }
        }
      },
      required: %w[pages],
      additionalProperties: false
    }.freeze

    def self.available_for?(document)
      offered_for?(document) && !document.needs_privacy_screening?
    end

    # Turned on and possible for this document, privacy rules aside.
    def self.offered_for?(document)
      settings = document.settings
      settings.blank_page_ai_check? && settings.task_configured?(:vision) && !document.private? &&
        !settings.provider_for(:vision).ocr_model?(settings.model_for(:vision))
    end

    def initialize(document)
      @document = document
    end

    def call(path, verdicts)
      unclear = verdicts.each_index.reject { |index| verdicts[index].sure }.map { |index| index + 1 }
      return verdicts if unclear.empty?

      Dir.mktmpdir do |dir|
        shown = unclear.flat_map { |page| [ page - 1, page ].select(&:positive?) }.uniq
        images = shown.map do |number|
          image_path = File.join(dir, "page-#{number}.jpg")
          File.binwrite(image_path, Pdf.render_page(path, number, edge: RENDER_EDGE))
          image_path
        end

        response = Outbound.for(@document)
          .chat(:vision)
          .with_schema(SCHEMA)
          .ask(prompt(unclear, shown), with: images)
        answers = response.parsed.fetch("pages").to_h { |answer| [ answer["page"].to_i, answer["blank"] ] }

        verdicts.each_with_index.map do |verdict, index|
          page = index + 1
          answers.key?(page) ? Verdict.new(blank: answers[page], sure: true) : verdict
        end
      end
    end

    private
      # Images reach the model without their file names, so the prompt says
      # which page each one is, and that the scan's own printed page numbers
      # do not count.
      def prompt(pages, shown)
        order = shown.each_with_index.map { |page, index| "image #{index + 1} is page #{page}" }.join(", ")
        <<~PROMPT
          These are pages from a scanned document, in this order: #{order}. Numbers printed on the pages
          themselves do not count. For each of pages #{pages.join(", ")}, decide whether it is blank. A page is blank when it carries no print of its own: an empty sheet,
          or one that only shows the previous page's print faintly and mirrored through the paper.
          A page printed in light or faded toner is not blank. Answer for exactly those pages.
        PROMPT
      end
  end
end
