# Tells which pages of a scan carry no print: nothing at all, or only what
# shows through from the other side of the sheet. Sheet feeders let blank
# sheets through, often with text bleeding through from the front, and those
# pages cost OCR time and tokens and put garbage in the text.
#
# A page also counts as blank when it only shows the page before it through
# the paper: a duplex scan puts each sheet's back right after its front, and
# heavy bleed-through can carry as much ink as faint print, so the front is
# what tells them apart.
module BlankPages
  class Detector
    # Large enough that a short line of text is still several pixels of
    # solid ink when a page is measured.
    RENDER_EDGE = 800

    def initialize(path, page_count)
      @path = path
      @page_count = page_count
    end

    def call
      verdicts = []
      previous = nil

      Pdf.render_gray_pages(@path, edge: RENDER_EDGE) do |paths|
        paths.first(@page_count).each_with_index do |page_path, index|
          current = MeasuredPage.new(Gray.read(page_path))
          # Only a printed page before this one can show through it.
          front = previous if index.positive? && !verdicts[index - 1].blank
          alone = current.ink.blank?
          blank = alone || current.shows_through?(front)
          sure = alone || current.ink.solid >= InkProfile::CONTENT_SOLID || !current.faint_beside?(front)
          verdicts << Verdict.new(blank: blank, sure: sure)
          previous = current
        end
      end

      verdicts
    end
  end
end
