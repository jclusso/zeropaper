# Checks the OCR stack inside the production image: renders a page of text
# to a scan with no text layer, reads it back with ocrmypdf and Tesseract,
# and reads a text layer and a thumbnail with poppler. Exits non-zero on any
# mismatch. Run with: bin/rails runner script/ocr_smoke.rb
require Rails.root.join("test/support/pdf_factory").to_s

def check(label)
  result = yield
  abort "FAIL #{label}" unless result
  puts "ok   #{label}"
end

text = "INVOICE NUMBER 4471\nAmount due 87 dollars\n"

Dir.mktmpdir do |dir|
  text_pdf = File.join(dir, "text.pdf")
  File.binwrite(text_pdf, PdfFactory.build([ text ]))
  check("poppler reads the text layer") { NativeText.pdf_pages(text_pdf).first.text.include?("INVOICE") }
  check("poppler renders a thumbnail") { Pdf.render_page(text_pdf, 1, edge: 640, format: :jpeg).bytesize.positive? }

  system("pdftoppm", "-gray", "-r", "200", "-singlefile", text_pdf, File.join(dir, "page"), exception: true)
  image = BlankPages::Gray.read(File.join(dir, "page.pgm"))
  canvas = PdfFactory::Canvas.new(image.width, image.height)
  canvas.pixels.replace(image.pixels)
  scan = File.join(dir, "scan.pdf")
  File.binwrite(scan, PdfFactory.build([ canvas ]))

  check("the scan has no text layer") { NativeText.pdf_pages(scan).first.text.squish.empty? }
  # The image has no database to read settings from.
  settings = Data.define(:straighten_pages) { alias_method :straighten_pages?, :straighten_pages }.new(straighten_pages: true)
  result = Ocr::Tesseract.new(settings).call(scan, pages: [ 1 ], content_type: "application/pdf", mode: :force)
  check("ocrmypdf and Tesseract read the scan") { result.text.include?("INVOICE") && result.text.include?("4471") }
  check("ocrmypdf writes a searchable PDF") { result.archive_path && NativeText.pdf_pages(result.archive_path).first.text.include?("INVOICE") }
  FileUtils.rm_rf(File.dirname(result.archive_path)) if result.archive_path
end
