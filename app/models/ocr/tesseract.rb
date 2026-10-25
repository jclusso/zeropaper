require "open3"

# Local OCR with ocrmypdf and Tesseract. Besides the text it writes a
# searchable PDF, which the viewer shows so text on a scan can be selected
# and found.
module Ocr
  class Tesseract
    LANGUAGE = "eng".freeze
    TIMEOUT = 30.minutes
    # :skip leaves pages that already carry text alone, :redo replaces a
    # scanner's OCR layer on image pages, :force rasterizes the chosen pages
    # and reads them again (for text layers that extract as garbage).
    MODES = { skip: "--skip-text", redo: "--redo-ocr", force: "--force-ocr" }.freeze

    def initialize(settings)
      @settings = settings
    end

    def call(path, pages:, content_type:, mode: :skip)
      dir = Dir.mktmpdir
      output = File.join(dir, "archive.pdf")
      sidecar = File.join(dir, "text.txt")

      command = [ "ocrmypdf", "--output-type", "pdf", "--optimize", "1",
        "--language", LANGUAGE, "--sidecar", sidecar, "--jobs", "2" ]
      command += [ "--image-dpi", "300" ] if content_type.start_with?("image/")
      command += [ "--pages", pages.join(",") ] if content_type == "application/pdf" && pages.any?
      files = [ path, output ]

      # A page tilted a degree or two splits table rows across lines.
      # Straightening redraws the page image, which :redo keeps as is, so a
      # scanner's OCR layer is replaced by reading its pages afresh. ocrmypdf
      # fails the whole file when Tesseract can't measure a page's tilt, as
      # on very low resolution scans, so a failed attempt is read again as
      # scanned.
      if @settings.straighten_pages?
        straight_mode = mode == :redo ? :force : mode
        _stdout, stderr, status = Pdf.capture(*command, MODES.fetch(straight_mode), "--deskew", *files, timeout: TIMEOUT)
      end
      _stdout, stderr, status = Pdf.capture(*command, MODES.fetch(mode), *files, timeout: TIMEOUT) unless status&.success? || status&.exitstatus == 6
      # Exit 6 means the file already had text everywhere; the copy is still written.
      raise Pdf::CommandFailed, "ocrmypdf failed: #{stderr.lines.last(3).join}".truncate(500) unless status.success? || status.exitstatus == 6

      texts = File.exist?(sidecar) ? File.read(sidecar).split("\f", -1) : []
      numbered = texts.each_with_index.to_h { |text, index| [ index + 1, text ] }
      FileUtils.rm_f(sidecar)
      return Result.new(pages: numbered.slice(*pages)) unless File.exist?(output)

      # The caller owns the directory from here and removes it with the PDF.
      result = Result.new(pages: numbered.slice(*pages), archive_path: output)
      dir = nil
      result
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end
end
