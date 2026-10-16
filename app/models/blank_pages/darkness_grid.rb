module BlankPages
  # A page shrunk to cells holding how far below the paper the page is on
  # average there.
  class DarknessGrid
    # Coarse enough that a sheet scanned a few millimetres off on each side
    # still lines up within MAX_SHIFT cells.
    EDGE = 120
    MAX_SHIFT = 8

    attr_reader :width, :height, :cells

    def initialize(image)
      histogram = Array.new(256, 0)
      image.pixels.each { |value| histogram[value] += 1 }
      paper = BlankPages.median(histogram, image.pixels.size)

      scale = EDGE.fdiv([ image.width, image.height ].max)
      @width = [ (image.width * scale).to_i, 1 ].max
      @height = [ (image.height * scale).to_i, 1 ].max
      @cells = Array.new(@width * @height, 0.0)
      counts = Array.new(@cells.size, 0)

      column_cells = (0...image.width).map { |x| [ @width - 1, (x * scale).to_i ].min }
      pixels = image.pixels
      image.height.times do |y|
        row_cell = [ @height - 1, (y * scale).to_i ].min * @width
        offset = y * image.width
        image.width.times do |x|
          cell = row_cell + column_cells[x]
          darkness = paper - pixels[offset + x]
          @cells[cell] += darkness if darkness.positive?
          counts[cell] += 1
        end
      end
      @cells.each_index { |index| @cells[index] /= counts[index] if counts[index].positive? }
    end

    # The best correlation with other, laid left-to-right reversed when
    # mirrored, over shifts of up to MAX_SHIFT cells either way.
    def match(other, mirrored:)
      best = -1.0
      (-MAX_SHIFT..MAX_SHIFT).each do |dy|
        (-MAX_SHIFT..MAX_SHIFT).each do |dx|
          correlation = correlate(other, mirrored, dx, dy)
          best = correlation if correlation && correlation > best
        end
      end
      best
    end

    private
      def correlate(other, mirrored, dx, dy)
        n = sum_a = sum_b = sum_aa = sum_bb = sum_ab = 0.0
        other_cells = other.cells
        other_width = other.width

        @height.times do |y|
          oy = y + dy
          next if oy.negative? || oy >= other.height

          row = y * @width
          other_row = oy * other_width
          @width.times do |x|
            ox = mirrored ? other_width - 1 - x + dx : x + dx
            next if ox.negative? || ox >= other_width

            a = @cells[row + x]
            b = other_cells[other_row + ox]
            n += 1
            sum_a += a
            sum_b += b
            sum_aa += a * a
            sum_bb += b * b
            sum_ab += a * b
          end
        end
        return if n.zero?

        variance_a = sum_aa / n - (sum_a / n)**2
        variance_b = sum_bb / n - (sum_b / n)**2
        return if variance_a <= 0 || variance_b <= 0

        (sum_ab / n - (sum_a / n) * (sum_b / n)) / Math.sqrt(variance_a * variance_b)
      end
  end
end
