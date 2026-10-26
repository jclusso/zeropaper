require "test_helper"

class BlankPages::DetectorTest < ActiveSupport::TestCase
  test "finds an empty sheet between printed pages" do
    pdf = scanned_pdf(PdfFactory.printed, PdfFactory.blank, PdfFactory.printed)

    verdicts = with_pdf_file(pdf) { |path| BlankPages::Detector.new(path, 3).call }

    assert_equal [ false, true, false ], verdicts.map(&:blank)
    assert verdicts[1].sure
  end

  test "finds the back of a duplex sheet that only shows its front through" do
    front = PdfFactory.printed
    pdf = scanned_pdf(front, front.mirrored_bleed(level: 140, every_nth_row: 3), PdfFactory.printed)

    verdicts = with_pdf_file(pdf) { |path| BlankPages::Detector.new(path, 3).call }

    assert_equal [ false, true, false ], verdicts.map(&:blank)
    refute verdicts[1].sure, "bleed-through is a judgement call a second opinion may overturn"
  end

  test "settles a light print after a blank back without a second opinion" do
    pdf = scanned_pdf(PdfFactory.printed, PdfFactory.blank, light_print, PdfFactory.blank)

    verdicts = with_pdf_file(pdf) { |path| BlankPages::Detector.new(path, 4).call }

    assert_equal [ false, true, false, true ], verdicts.map(&:blank)
    assert verdicts.all?(&:sure), "nothing before the third page can show through it"
  end

  test "settles a light first page without a second opinion" do
    pdf = scanned_pdf(light_print, PdfFactory.printed)

    verdicts = with_pdf_file(pdf) { |path| BlankPages::Detector.new(path, 2).call }

    assert_equal [ false, false ], verdicts.map(&:blank)
    assert verdicts.first.sure
  end

  test "keeps every page of a fully printed document" do
    pdf = scanned_pdf(PdfFactory.printed, PdfFactory.printed)

    verdicts = with_pdf_file(pdf) { |path| BlankPages::Detector.new(path, 2).call }

    assert_equal [ false, false ], verdicts.map(&:blank)
  end

  private
    # Print in a grey toner: ink, but none of it near-black.
    def light_print
      PdfFactory.printed.tap { |canvas| canvas.pixels.map! { |value| value < 128 ? 120 : value } }
    end
end
