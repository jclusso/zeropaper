require "open3"

# Finds pages scanned upside down or sideways with Tesseract's orientation
# detection (OSD), locally. A result is the clockwise turn in degrees that
# makes a page upright.
module Orientation
  # Full pages of text score 9 to 13 when read the right way round; a page
  # with two short lines scores about 1.5 even when it reads correctly. Below
  # this the page is left alone, since turning an upright page upside down is
  # worse than missing a turn.
  MIN_CONFIDENCE = 2.0
  # Long enough edge for OSD to read body text at roughly 200 dpi.
  RENDER_EDGE = 2_000
  RENDER_DPI = 200
  ROTATIONS = [ 90, 180, 270 ].freeze

  extend self

  # Clockwise turn per page (1-based) for the pages of a PDF that need one.
  # Pages with a readable text layer are skipped: they were made digitally
  # or already OCR'd, and their text reads whichever way they are shown.
  def pdf_rotations(path, page_count)
    text_pages = Pdf.text_pages(path)

    (1..page_count).each_with_object({}) do |page, rotations|
      next if text_pages[page - 1].to_s.squish.length >= NativeText::MIN_PAGE_CHARACTERS

      degrees = Dir.mktmpdir do |dir|
        image = File.join(dir, "page.png")
        File.binwrite(image, Pdf.render_page(path, page, edge: RENDER_EDGE, format: :png))
        image_rotation(image)
      end
      rotations[page] = degrees if degrees
    end
  end

  # Clockwise turn for an image file, or nil when it is upright or OSD is unsure.
  def image_rotation(path)
    output, errors, status = Pdf.capture("tesseract", path.to_s, "stdout", "--psm", "0", "--dpi", RENDER_DPI.to_s, timeout: 2.minutes)
    output += errors
    # Tesseract exits non-zero on pages with too few characters to judge.
    return unless status.success?

    degrees = output[/^Rotate:\s*(\d+)/, 1].to_i
    confidence = output[/^Orientation confidence:\s*([\d.]+)/, 1].to_f
    degrees if degrees.in?(ROTATIONS) && confidence >= MIN_CONFIDENCE
  rescue Pdf::CommandFailed
    nil
  end
end
