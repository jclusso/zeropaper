# OCR by the vision task's model. A dedicated OCR model (such as Mistral
# Document OCR) goes through the OCR API; any other model reads the PDF or
# image in a chat.
module Ocr
  class AI
    PAGE_MARKER = /^=== PAGE (\d+) ===\s*$/
    FENCE = /\A\s*```[\w-]*[ \t]*\n?|\n?```\s*\z/

    # Chat models sometimes wrap their answer, or each page, in a Markdown
    # code block even when told not to.
    def self.unfence(text)
      text.to_s.gsub(FENCE, "")
    end

    def initialize(settings, document)
      @settings = settings
      @document = document
    end

    def call(path, pages:, content_type:)
      outbound = Outbound.for(@document)
      Ocr.with_selected_pages(path, pages, content_type) do |file_path, numbers|
        if @settings.provider_for(:vision).ocr_model?(@settings.model_for(:vision))
          result = outbound.ocr(file_path)
          next Result.new(pages: result.pages.to_h { |page| [ numbers.fetch(page.index), page.markdown.to_s ] })
        end

        response = outbound.chat(:vision)
          .with_instructions(instructions)
          .ask("Transcribe all #{numbers.size} #{"page".pluralize(numbers.size)}.", with: file_path)
        Result.new(pages: split(response.content.to_s, numbers))
      end
    end

    private
      def instructions
        <<~TEXT
          You transcribe scanned documents. Output the text of every page exactly as written, in reading
          order, as Markdown. Keep tables as Markdown tables. Do not summarize, translate, correct or
          add commentary, and do not wrap the output in code blocks. Start each page with a line
          `=== PAGE n ===`, numbering pages from 1.
        TEXT
      end

      def split(text, numbers)
        text = self.class.unfence(text)
        parts = text.split(PAGE_MARKER)
        return { numbers.first => text.strip } if parts.size < 3

        parts.drop(1).each_slice(2).each_with_object({}) do |(index, page_text), pages|
          number = numbers[index.to_i - 1]
          pages[number] = self.class.unfence(page_text).strip if number
        end
      end
  end
end
