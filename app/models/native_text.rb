# Reads text that is already in the file: plain text, Word, spreadsheets, and
# PDF pages whose text layer is real. Embedded text on a scanned page usually
# comes from the scanner's own OCR, and some PDFs extract as garbage, so those
# pages are left for OCR instead.
module NativeText
  WORD_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document".freeze
  SPREADSHEET_TYPES = [ "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "text/csv" ].freeze
  TEXT_TYPES = %w[text/plain text/markdown].freeze

  # Spreadsheets stop here; the rest is left out of the text and the viewer.
  MAX_ROWS = 50_000
  MAX_CELLS = 1_000_000

  # A PDF page with fewer characters than this is treated as an image.
  MIN_PAGE_CHARACTERS = 40
  # A page whose largest image covers this much of it is a scan.
  SCANNED_COVERAGE = 0.8
  # Readable text is mostly letters, digits, spaces and common punctuation.
  CLEAN_SHARE = 0.85
  CLEAN_CHARACTER = /[A-Za-z0-9\s.,;:!?'"()\[\]$%&\/@#*+=<>_~^|{}`\\\-–—•·€£¥°§©®™‘’“”…]/

  # One page of a PDF's text layer and whether it can be used as is.
  PdfPage = Struct.new(:number, :text, :scanned, :readable, keyword_init: true) do
    def trusted?
      readable && !scanned
    end
  end

  extend self

  def extract(path, content_type)
    case content_type
    when "application/pdf" then pdf(path)
    when *TEXT_TYPES then [ read_utf8(path) ]
    when WORD_TYPE then [ word(path) ]
    when *SPREADSHEET_TYPES then spreadsheet(path, content_type)
    end
  end

  # Rows of each sheet, for the viewer and for text extraction, up to
  # MAX_ROWS per sheet and MAX_CELLS in all.
  def sheets(path, content_type)
    book = open_spreadsheet(path, content_type)
    cells = 0
    book.sheets.map do |name|
      sheet = book.sheet(name)
      rows = []
      if sheet.first_row
        (sheet.first_row..[ sheet.last_row, sheet.first_row + MAX_ROWS - 1 ].min).each do |number|
          break if cells >= MAX_CELLS

          row = sheet.row(number).map(&:to_s)
          cells += row.size
          rows << row
        end
      end
      { name: name, rows: rows }
    end
  end

  def pdf_pages(path)
    coverage = Pdf.image_coverage(path)
    Pdf.text_pages(path).each_with_index.map do |text, index|
      number = index + 1
      PdfPage.new(number: number, text: text, scanned: coverage[number] >= SCANNED_COVERAGE, readable: readable?(text))
    end
  end

  def readable?(text)
    text = text.to_s.squish
    return false if text.length < MIN_PAGE_CHARACTERS
    return false if text.include?("(cid:") || text.count("\uFFFD") > 2

    clean = text.each_char.count { |character| character.match?(CLEAN_CHARACTER) }
    return false if clean.fdiv(text.length) < CLEAN_SHARE

    words = text.scan(/[[:alpha:]]{2,}/)
    words.size >= 3 && words.count { |word| word.match?(/[aeiouy]/i) }.fdiv(words.size) >= 0.7
  end

  private
    # The whole PDF's text when every page with content can be trusted.
    def pdf(path)
      pages = pdf_pages(path)
      return if pages.empty?
      return unless pages.all? { |page| page.trusted? || (page.text.squish.empty? && !page.scanned) }

      pages.map(&:text)
    end

    def word(path)
      UploadLimit.check_zip!(path)
      Docx::Document.open(path).paragraphs.map(&:text).join("\n")
    end

    def spreadsheet(path, content_type)
      sheets(path, content_type).map do |sheet|
        ([ "## #{sheet[:name]}" ] + sheet[:rows].map { |row| row.join("\t") }).join("\n")
      end
    end

    def open_spreadsheet(path, content_type)
      extension = content_type == "text/csv" ? :csv : :xlsx
      UploadLimit.check_zip!(path) if extension == :xlsx
      Roo::Spreadsheet.open(path, extension: extension)
    end

    def read_utf8(path)
      File.read(path, mode: "rb").force_encoding(Encoding::UTF_8).scrub
    end
end
