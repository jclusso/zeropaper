# A second opinion for pages the local check cannot settle, where heavy
# bleed-through and faint print look alike. One request per document, each
# unclear page sent with the page before it. Off by default because it spends
# tokens, and never offered for private documents.
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
        images = unclear.flat_map do |page|
          [ page - 1, page ].select(&:positive?).map do |number|
            image_path = File.join(dir, "page-#{number}.jpg")
            File.binwrite(image_path, Pdf.render_page(path, number, edge: RENDER_EDGE))
            image_path
          end.uniq
        end.uniq

        response = Outbound.for(@document)
          .chat(:vision)
          .with_schema(SCHEMA)
          .ask(prompt(unclear), with: images)
        answers = response.parsed.fetch("pages").to_h { |answer| [ answer["page"].to_i, answer["blank"] ] }

        verdicts.each_with_index.map do |verdict, index|
          page = index + 1
          answers.key?(page) ? Verdict.new(blank: answers[page], sure: true) : verdict
        end
      end
    end

    private
      def prompt(pages)
        <<~PROMPT
          These are pages from a scanned document, named page-N.jpg. For each of pages #{pages.join(", ")},
          decide whether it is blank. A page is blank when it carries no print of its own: an empty sheet,
          or one that only shows the previous page's print faintly and mirrored through the paper.
          A page printed in light or faded toner is not blank. Answer for exactly those pages.
        PROMPT
      end
  end
end
