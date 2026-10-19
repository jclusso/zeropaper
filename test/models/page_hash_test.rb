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

  test "pairs pages in order, leaving gaps for pages only one document has" do
    a, b, c = %w[a b c].map { |letter| letter * 64 }
    d = "0" * 64

    assert_equal [ [ 1, 1 ], [ nil, 2 ], [ 2, 3 ] ], PageHash.pair([ a, c ], [ a, b, c ])
    assert_equal [ [ 1, 1 ], [ 2, nil ], [ 3, 2 ] ], PageHash.pair([ a, b, c ], [ a, c ])
    assert_equal [ [ 1, nil ], [ nil, 1 ] ], PageHash.pair([ a ], [ d ])
    assert_equal [ [ nil, 1 ] ], PageHash.pair([], [ a ])
  end

  test "pairs the closest pages, allowing more apart than a match alone" do
    page, rescan, other_rescan, different = [ 0, 20, 24, 40 ].map { |bits| ("f" * (bits / 4)).ljust(64, "0") }

    assert_equal [ [ nil, 1 ], [ 1, 2 ] ], PageHash.pair([ page ], [ other_rescan, rescan ])
    assert_equal [ [ 1, 1 ], [ nil, 2 ] ], PageHash.pair([ page ], [ rescan, other_rescan ])
    assert_equal [ [ 1, nil ], [ nil, 1 ] ], PageHash.pair([ page ], [ different ])
  end

  test "a block can rule out pairs the hashes allow" do
    a, c = "a" * 64, "c" * 64

    assert_equal [ [ 1, nil ], [ nil, 1 ], [ 2, 2 ] ], PageHash.pair([ a, c ], [ a, c ]) { |i, j| !(i.zero? && j.zero?) }
  end

  private
    # Scanner dust: a scattering of dark specks on an otherwise identical page.
    def speckled(canvas)
      random = Random.new(1)
      300.times { canvas.rect(random.rand(canvas.width), random.rand(canvas.height), 2, 2, 0) }
      canvas
    end
end
