require "test_helper"

class Document::OrientationTest < ActiveSupport::TestCase
  PAGE_TEXT = <<~TEXT.freeze
    Acme Power Company
    Electricity statement for the billing period ending March 14, 2026
    You used 412 kWh this month, which is less than the same month last year.
    Amount due: $87.40 by April 1, 2026. Account number 55-0192.
    Please pay on time to avoid late fees and interruptions to your service.
    Questions about this statement can be answered by our customer service team.
    Thank you for being a customer of Acme Power Company for eleven years.
  TEXT

  test "tesseract can detect orientation here" do
    output, _status = Open3.capture2e("tesseract", "--list-langs")
    assert_includes output.lines.map(&:strip), "osd"
  end

  test "detects pages scanned upside down and sideways" do
    upright = text_canvas
    with_pdf_file(scanned_pdf(upright, rotate(upright, 180), PdfFactory.blank)) do |path|
      assert_equal({ 2 => 180 }, Orientation.pdf_rotations(path, 3))
    end

    Dir.mktmpdir do |dir|
      sideways = File.join(dir, "sideways.png")
      ImageProcessing::Vips.source(png(upright, dir)).rotate(90).call(destination: sideways)
      assert_equal 270, Orientation.image_rotation(sideways)
      assert_nil Orientation.image_rotation(png(upright, dir))
    end
  end

  test "pages with a text layer are not checked" do
    with_pdf_file(text_pdf(PAGE_TEXT)) do |path|
      Orientation.expects(:image_rotation).never
      assert_empty Orientation.pdf_rotations(path, 1)
    end
  end

  test "processing turns an upside-down page in the stored file before OCR" do
    upright = text_canvas
    document = ingest(scanned_pdf(upright, rotate(upright, 180)), filename: "statement.pdf")
    uploaded_checksum = document.checksum

    process(document)

    assert_equal({ "2" => 180 }, document.page_record["rotated"])
    assert_equal "Turned page 2", document.step_state("orientation")["detail"]
    assert document.original_file.attached?
    assert_not_equal uploaded_checksum, document.checksum

    document.file.open do |file|
      assert_empty Orientation.pdf_rotations(file.path, 2)
    end
    assert_match "Electricity statement", document.page_texts[1]
  end

  test "an upright document is left alone" do
    document = ingest(scanned_pdf(text_canvas), filename: "upright.pdf")

    process(document)

    assert_equal "All pages upright", document.step_state("orientation")["detail"]
    refute document.original_file.attached?
    assert_nil document.page_record["rotated"]
  end

  test "a sideways photo is turned upright" do
    image = Dir.mktmpdir do |dir|
      sideways = File.join(dir, "sideways.png")
      ImageProcessing::Vips.source(png(text_canvas, dir)).rotate(90).call(destination: sideways)
      File.binread(sideways)
    end
    document = ingest(image, filename: "photo.png")

    process(document)

    assert_equal({ "1" => 270 }, document.page_record["rotated"])
    document.file.open { |file| assert_nil Orientation.image_rotation(file.path) }
    assert_match "Electricity statement", document.content
  end

  test "private documents are turned locally" do
    configure_openai
    upright = text_canvas
    document = ingest(scanned_pdf(rotate(upright, 180)), filename: "private.pdf", private: true, private_reason: "test")

    process(document)

    assert_equal({ "1" => 180 }, document.page_record["rotated"])
    assert_equal "test_private", document.file.blob.service_name
    assert_no_external_requests
  end

  private
    def text_canvas
      with_pdf_file(text_pdf(PAGE_TEXT)) do |path|
        Dir.mktmpdir do |dir|
          system("pdftoppm", "-gray", "-r", "150", "-singlefile", path, File.join(dir, "page"), exception: true)
          image = BlankPages::Gray.read(File.join(dir, "page.pgm"))
          PdfFactory::Canvas.new(image.width, image.height).tap { |canvas| canvas.pixels.replace(image.pixels) }
        end
      end
    end

    def rotate(canvas, degrees)
      raise ArgumentError unless degrees == 180

      PdfFactory::Canvas.new(canvas.width, canvas.height).tap { |turned| turned.pixels.replace(canvas.pixels.reverse) }
    end

    def png(canvas, dir)
      path = File.join(dir, "page-#{SecureRandom.hex(4)}.png")
      Vips::Image.new_from_memory(canvas.pixels.pack("C*"), canvas.width, canvas.height, 1, :uchar).write_to_file(path)
      path
    end
end
