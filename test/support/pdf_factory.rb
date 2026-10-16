require "zlib"

# Builds small PDFs in Ruby so tests need no fixture files: text pages carry
# a real text layer, image pages are grayscale scans with none.
module PdfFactory
  PAGE_WIDTH = 612
  PAGE_HEIGHT = 792

  # A grayscale canvas that becomes a BlankPages::Gray or a scanned PDF page.
  class Canvas
    attr_reader :width, :height, :pixels

    def initialize(width, height, paper: 255)
      @width, @height = width, height
      @pixels = Array.new(width * height, paper)
    end

    def rect(x, y, w, h, level, every_nth_row: 1)
      (y...[ y + h, height ].min).each do |row|
        next unless ((row - y) % every_nth_row).zero?

        (x...[ x + w, width ].min).each { |column| pixels[row * width + column] = level }
      end
      self
    end

    # Horizontally mirrored copy, with dark pixels lightened to level.
    def mirrored_bleed(level:, paper: 255, every_nth_row: 1)
      copy = Canvas.new(width, height, paper: paper)
      height.times do |row|
        next unless (row % every_nth_row).zero?

        width.times do |column|
          copy.pixels[row * width + (width - 1 - column)] = level if pixels[row * width + column] < paper - 100
        end
      end
      copy
    end

    def to_gray
      BlankPages::Gray.new(width, height, pixels.dup)
    end
  end

  # Lines of black blocks shaped like a page of text, asymmetric so mirroring changes it.
  def self.printed(width: 400, height: 520)
    canvas = Canvas.new(width, height)
    12.times do |line|
      length = 60 + (line * 37 % 220)
      canvas.rect(40, 50 + line * 34, length, 10, 0)
    end
    canvas.rect(250, 440, 110, 50, 0)
    canvas
  end

  def self.blank(width: 400, height: 520)
    Canvas.new(width, height)
  end

  # pages: strings for text pages, Canvas objects for scanned pages.
  def self.build(pages)
    objects = []
    add = ->(body) { objects << body; objects.size }

    catalog = add.("") # filled in below
    pages_ref = add.("")
    font = add.("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

    page_refs = pages.map do |page|
      resources, content =
        if page.is_a?(Canvas)
          data = Zlib::Deflate.deflate(page.pixels.pack("C*"))
          image = add.("<< /Type /XObject /Subtype /Image /Width #{page.width} /Height #{page.height} /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode /Length #{data.bytesize} >>\nstream\n#{data}\nendstream")
          [ "<< /XObject << /Im1 #{image} 0 R >> >>", "q #{PAGE_WIDTH} 0 0 #{PAGE_HEIGHT} 0 0 cm /Im1 Do Q" ]
        else
          lines = page.to_s.lines.map { |line| "(#{line.chomp.gsub(/([()\\])/, "\\\\\\1")}) Tj 0 -18 Td" }
          [ "<< /Font << /F1 #{font} 0 R >> >>", "BT /F1 12 Tf 72 720 Td #{lines.join(" ")} ET" ]
        end
      stream = add.("<< /Length #{content.bytesize} >>\nstream\n#{content}\nendstream")
      add.("<< /Type /Page /Parent #{pages_ref} 0 R /MediaBox [0 0 #{PAGE_WIDTH} #{PAGE_HEIGHT}] /Resources #{resources} /Contents #{stream} 0 R >>")
    end

    objects[catalog - 1] = "<< /Type /Catalog /Pages #{pages_ref} 0 R >>"
    objects[pages_ref - 1] = "<< /Type /Pages /Kids [#{page_refs.map { |ref| "#{ref} 0 R" }.join(" ")}] /Count #{page_refs.size} >>"

    pdf = +"%PDF-1.4\n%\xE2\xE3\xCF\xD3\n".b
    offsets = objects.each_with_index.map do |body, index|
      offset = pdf.bytesize
      pdf << "#{index + 1} 0 obj\n".b << body.b << "\nendobj\n".b
      offset
    end
    xref = pdf.bytesize
    pdf << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n".b
    offsets.each { |offset| pdf << format("%010d 00000 n \n", offset).b }
    pdf << "trailer\n<< /Size #{objects.size + 1} /Root #{catalog} 0 R >>\nstartxref\n#{xref}\n%%EOF\n".b
    pdf
  end

  module Helpers
    def text_pdf(*pages)
      PdfFactory.build(pages)
    end

    def scanned_pdf(*canvases)
      PdfFactory.build(canvases)
    end

    def with_pdf_file(data)
      Tempfile.create([ "test", ".pdf" ], binmode: true) do |file|
        file.write(data)
        file.flush
        yield file.path
      end
    end
  end
end
