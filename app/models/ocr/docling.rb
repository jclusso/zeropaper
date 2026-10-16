# Local layout-aware OCR through the docling-serve container in the compose
# file. Counts as local: it runs next to the app and keeps nothing.
module Ocr
  class Docling
    PAGE_BREAK = "<!-- zeropaper:page-break -->".freeze

    def initialize(settings)
      @settings = settings
    end

    def call(path, pages:, content_type:)
      Ocr.with_selected_pages(path, pages, content_type) do |file_path, numbers|
        markdown = convert(file_path, content_type)
        texts = markdown.split(PAGE_BREAK)
        Result.new(pages: numbers.each_with_index.to_h { |number, index| [ number, texts[index].to_s ] })
      end
    end

    private
      def convert(path, content_type)
        form = {
          files: { body: File.open(path), filename: File.basename(path), content_type: content_type },
          to_formats: "md",
          do_ocr: "true",
          image_export_mode: "placeholder",
          md_page_break_placeholder: PAGE_BREAK,
          ocr_lang: "en"
        }

        response = HttpRequest.post("#{@settings.docling_url.chomp("/")}/v1/convert/file", form: form, read_timeout: 900)
        response.raise_for_status
        body = response.json
        raise Pdf::CommandFailed, "Docling: #{Array(body["errors"]).join(", ")}" if body["status"] == "failure"

        body.dig("document", "md_content").to_s
      end
  end
end
