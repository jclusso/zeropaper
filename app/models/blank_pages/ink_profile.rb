module BlankPages
  class InkProfile
    # How much darker than the paper a pixel must be to count as ink. Light
    # bleed-through is a grey a few dozen levels below the paper and falls
    # short of it.
    INK_CONTRAST = 100
    # Near-black ink. Print reaches it; text seen through the sheet rarely does.
    SOLID_CONTRAST = 160
    # Trimmed from every edge before measuring: scanner bed edges, shadows and
    # punch holes live there and are not content.
    MARGIN_SHARE = 0.06

    # A page with less ink than this is blank. A page holding only a short
    # line of 18pt text sits several times above it.
    BLANK_INK = 0.0002
    # A page with little ink, almost none of it near-black, is blank: a stamp
    # or pen mark pressed through from the front.
    FAINT_INK = 0.001
    FAINT_SOLID = 0.0001
    # The near-black share past which a page is printed beyond doubt. Printed
    # pages measure from 0.3% (a scanner that renders toner as a light grey)
    # to over 2%, and the heaviest bleed-through seen so far 0.5%.
    CONTENT_SOLID = 0.015

    attr_reader :ink, :solid

    # Compares every pixel with the paper, which is the median level, so
    # tinted paper and a grey scanner background are measured against
    # themselves rather than pure white.
    def self.measure(image)
      mx = (image.width * MARGIN_SHARE).to_i
      my = (image.height * MARGIN_SHARE).to_i
      x0, x1, y0, y1 = mx, image.width - mx, my, image.height - my
      return new(0.0, 0.0) if x1 <= x0 || y1 <= y0

      histogram = Array.new(256, 0)
      pixels = image.pixels
      (y0...y1).each do |y|
        row = y * image.width
        (x0...x1).each { |x| histogram[pixels[row + x]] += 1 }
      end
      total = (x1 - x0) * (y1 - y0)
      paper = BlankPages.median(histogram, total)

      ink = histogram.first([ paper - INK_CONTRAST, 0 ].max).sum
      solid = histogram.first([ paper - SOLID_CONTRAST, 0 ].max).sum
      new(ink.fdiv(total), solid.fdiv(total))
    end

    def initialize(ink, solid)
      @ink, @solid = ink, solid
    end

    # Blank on its own: next to no ink at all, or a few faint marks. Faint
    # ink across the whole page is not enough, because a page printed in
    # light toner looks exactly like heavy bleed-through; only the page
    # before it or a second opinion can tell them apart.
    def blank?
      ink < BLANK_INK || (ink < FAINT_INK && solid < FAINT_SOLID)
    end
  end
end
