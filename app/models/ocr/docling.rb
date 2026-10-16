# Local layout-aware OCR through the docling-serve container in the compose
# file. Counts as local only while its address is on this machine or the
# local network: it runs next to the app and keeps nothing. Every request
# checks that again, whatever the document, since Docling also reads
# shareable documents for the local privacy screen, and is pinned to the
# addresses that were checked.
module Ocr
  class Docling
    PAGE_BREAK = "<!-- zeropaper:page-break -->".freeze

    class NotLocalError < StandardError; end

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
        url = "#{@settings.docling_url.to_s.chomp("/")}/v1/convert/file"
        addresses = LocalNetwork.addresses(url)
        raise NotLocalError, "Docling at #{@settings.docling_url} is not on this machine or the local network, so no document is sent to it" unless addresses

        form = {
          files: { body: File.open(path), filename: File.basename(path), content_type: content_type },
          to_formats: "md",
          do_ocr: "true",
          image_export_mode: "placeholder",
          md_page_break_placeholder: PAGE_BREAK,
          ocr_lang: "en"
        }

        response = HttpRequest.post(url, form: form, read_timeout: 900, addresses: addresses)
        response.raise_for_status
        body = response.json
        raise Pdf::CommandFailed, "Docling: #{Array(body["errors"]).join(", ")}" if body["status"] == "failure"

        body.dig("document", "md_content").to_s
      end
  end
end
