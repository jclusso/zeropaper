module Ocr
  # Text read from the pages that were sent, keyed by page number.
  Result = Struct.new(:pages, :archive_path, keyword_init: true) do
    def text
      pages.values.join("\n\n")
    end

    # One entry per page of the document; pages not read are empty.
    def texts_for(page_count)
      (1..[ page_count, 1 ].max).map { |page| pages.fetch(page, "").to_s.strip }
    end
  end

  def self.engine(provider, settings, document: nil)
    case provider
    when "tesseract" then Tesseract.new(settings)
    when "docling" then Docling.new(settings)
    when "ai" then AI.new(settings, document)
    else raise ArgumentError, "unknown OCR provider #{provider}"
    end
  end

  # Engines that take a whole file get only the pages to read. Yields the
  # path to send and the document page number of each page in it.
  def self.with_selected_pages(path, pages, content_type)
    return yield(path, [ 1 ]) unless content_type == "application/pdf"

    all = (1..Pdf.page_count(path)).to_a
    return yield(path, all) if pages == all

    Dir.mktmpdir do |dir|
      subset = File.join(dir, "pages.pdf")
      Pdf.only_pages(path, pages, subset)
      yield subset, pages
    end
  end
end
