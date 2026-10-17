require "test_helper"

class PageHashTest < ActiveSupport::TestCase
  test "two scans of the same page hash alike" do
    page = PageHash.of(PdfFactory.printed.to_gray)
    rescan = PageHash.of(speckled(PdfFactory.printed).to_gray)

    assert_operator PageHash.distance(page, rescan), :<=, PageHash::SAME_PAGE_BITS
  end

  test "pages with different print hash apart" do
    page = PageHash.of(PdfFactory.printed.to_gray)
    other = PageHash.of(PdfFactory.blank.rect(40, 300, 320, 180, 0).to_gray)

    assert_operator PageHash.distance(page, other), :>, PageHash::SAME_PAGE_BITS
  end

  test "hashes each page of a PDF, leaving out skipped pages" do
    pdf = scanned_pdf(PdfFactory.printed, PdfFactory.blank, PdfFactory.printed)

    hashes = with_pdf_file(pdf) { |path| PageHash.pdf_pages(path, skip: [ 2 ]) }

    assert_equal 2, hashes.size
    assert_equal PageHash::SIZE * PageHash::SIZE / 4, hashes.first.length
  end

  test "a copy without some pages matches the full scan" do
    front = PageHash.of(PdfFactory.printed.to_gray)
    back = PageHash.of(PdfFactory.blank.rect(40, 300, 320, 180, 0).to_gray)

    assert PageHash.same_pages?([ front ], [ front, back ])
    refute PageHash.same_pages?([ back ], [ front ])
    refute PageHash.same_pages?([], [ front ])
  end

  private
    # Scanner dust: a scattering of dark specks on an otherwise identical page.
    def speckled(canvas)
      random = Random.new(1)
      300.times { canvas.rect(random.rand(canvas.width), random.rand(canvas.height), 2, 2, 0) }
      canvas
    end
end
