# A fingerprint of how a page looks, so two scans of the same sheet can be
# matched when OCR reads them differently. Each page is shrunk to a 17 by 16
# grid of average brightness and every bit records whether a cell is clearly
# brighter than the one to its right: scan noise, compression and exposure
# average out and the layout of print on the page is what remains.
#
# Forms from one template look alike too, so a matching page alone never
# makes a duplicate; Document::Searchable also asks for the same numbers.
module PageHash
  SIZE = 16
  RENDER_EDGE = 400
  # Brightness steps smaller than this read as flat, so plain paper hashes
  # the same on every scan instead of flipping with its noise.
  EDGE = 4
  # Rescans of one page measured up to 11 of the 256 bits apart, inspection
  # reports from one template 20 or more.
  SAME_PAGE_BITS = 16

  module_function

  # Hex hashes of the pages of a PDF, in page order, leaving out skip
  # (1-based page numbers).
  def pdf_pages(path, skip: [])
    Pdf.render_gray_pages(path, edge: RENDER_EDGE) do |paths|
      paths.each_with_index.filter_map { |page_path, index| of(BlankPages::Gray.read(page_path)) unless (index + 1).in?(skip) }
    end
  end

  def of(gray)
    bits = grid(gray, SIZE + 1, SIZE).flat_map { |row| row.each_cons(2).map { |left, right| left > right + EDGE ? 1 : 0 } }
    bits.join.to_i(2).to_s(16).rjust(SIZE * SIZE / 4, "0")
  end

  def distance(hash, other)
    (hash.to_i(16) ^ other.to_i(16)).to_s(2).count("1")
  end

  # Whether every page of the shorter document looks like some page of the
  # other, so a copy with its blank backs removed still matches.
  def same_pages?(hashes, other)
    shorter, longer = [ hashes, other ].sort_by(&:size)
    shorter.any? && shorter.all? { |hash| longer.any? { |candidate| distance(hash, candidate) <= SAME_PAGE_BITS } }
  end

  # Pairs the pages of two documents in order, as [page, other_page] with
  # 1-based numbers, matching as many as it can. A page with no match in
  # the other document is paired with nil, so a copy with pages removed
  # lines up with the full scan around the gaps. A block, given 0-based
  # indexes, can rule out pairs the hashes alone would allow.
  def pair(hashes, other, &allowed)
    same = ->(i, j) { distance(hashes[i], other[j]) <= SAME_PAGE_BITS && (allowed.nil? || allowed.call(i, j)) }
    lengths = Array.new(hashes.size + 1) { Array.new(other.size + 1, 0) }
    hashes.size.downto(1) do |i|
      other.size.downto(1) do |j|
        lengths[i - 1][j - 1] =
          if same.(i - 1, j - 1) then lengths[i][j] + 1
          else [ lengths[i][j - 1], lengths[i - 1][j] ].max
          end
      end
    end

    pairs, i, j = [], 0, 0
    while i < hashes.size || j < other.size
      if i < hashes.size && j < other.size && same.(i, j) && lengths[i][j] == lengths[i + 1][j + 1] + 1
        pairs << [ i += 1, j += 1 ]
      elsif j == other.size || (i < hashes.size && lengths[i + 1][j] >= lengths[i][j + 1])
        pairs << [ i += 1, nil ]
      else
        pairs << [ nil, j += 1 ]
      end
    end
    pairs
  end

  # Average brightness of each cell when gray is cut into columns by rows.
  def grid(gray, columns, rows)
    (0...rows).map do |row|
      top, bottom = span(row, rows, gray.height)
      (0...columns).map do |column|
        left, right = span(column, columns, gray.width)
        sum = (top...bottom).sum { |y| gray.pixels[y * gray.width + left, right - left].sum }
        sum.fdiv((bottom - top) * (right - left))
      end
    end
  end

  def span(index, count, length)
    start = index * length / count
    [ start, [ (index + 1) * length / count, start + 1 ].max ]
  end
end
