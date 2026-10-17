require "test_helper"
require "vips"

class Ingest::CompletenessTest < ActiveSupport::TestCase
  test "a PDF is complete once %%EOF is written, even with padding after it" do
    pdf = text_pdf("Statement")

    assert_equal :complete, completeness(pdf)
    assert_equal :complete, completeness(pdf + "\0" * 200)
    assert_equal :incomplete, completeness(pdf.byteslice(0, pdf.bytesize - 7))
    assert_equal :incomplete, completeness(pdf.byteslice(0, pdf.bytesize / 2))
  end

  test "a JPEG is complete once the end marker follows the image data" do
    jpeg = image("jpg")

    assert_equal :complete, completeness(jpeg)
    assert_equal :complete, completeness(jpeg + "camera trailer".b * 100_000)
    assert_equal :incomplete, completeness(jpeg.byteslice(0, jpeg.bytesize - 2))
    assert_equal :incomplete, completeness(jpeg.byteslice(0, 100))
  end

  test "a JPEG cut off after an embedded thumbnail is incomplete" do
    jpeg = image("jpg")
    thumbnail = "\xFF\xD8\xFF\xD9".b
    exif = "\xFF\xE1".b + [ thumbnail.bytesize + 2 ].pack("n") + thumbnail
    with_thumbnail = jpeg.byteslice(0, 2) + exif + jpeg.byteslice(2..)

    assert_equal :complete, completeness(with_thumbnail)
    assert_equal :incomplete, completeness(with_thumbnail.byteslice(0, 2 + exif.bytesize))
  end

  test "a PNG is complete once its end chunk is written" do
    png = image("png")

    assert_equal :complete, completeness(png)
    assert_equal :incomplete, completeness(png.byteslice(0, png.bytesize - 12))
  end

  test "a WebP is complete once it reaches the size its header gives" do
    webp = image("webp")

    assert_equal :complete, completeness(webp)
    assert_equal :incomplete, completeness(webp.byteslice(0, webp.bytesize - 1))
  end

  test "a HEIC is complete when its boxes end where the file does" do
    heic = box("ftyp", "heic\0\0\0\0mif1heic") + box("meta", "\0" * 40) + box("mdat", "x" * 500)

    assert_equal :complete, completeness(heic)
    assert_equal :incomplete, completeness(heic.byteslice(0, heic.bytesize - 100))
    assert_nil completeness(heic.byteslice(0, heic.bytesize - 508) + [ 0 ].pack("N") + "mdat" + "x" * 200)
  end

  test "a Word file is complete once the zip's end record points back at its directory" do
    docx = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("word/document.xml")
      zip.write("<w:document>Statement</w:document>")
    end.string

    assert_equal :complete, completeness(docx)
    assert_equal :incomplete, completeness(docx.byteslice(0, docx.bytesize - 10))
    assert_equal :incomplete, completeness(docx.byteslice(0, docx.bytesize / 2))
  end

  test "TIFF and text cannot be judged" do
    assert_nil completeness(image("tif"))
    assert_nil completeness("Statement for October")
    assert_nil completeness("")
  end

  private
    def completeness(data)
      Tempfile.create("ingest", binmode: true) do |file|
        file.write(data)
        file.flush
        Ingest::Completeness.of(file)
      end
    end

    def image(format)
      Vips::Image.black(64, 64).add(200).cast(:uchar).write_to_buffer(".#{format}")
    end

    def box(type, payload)
      [ payload.bytesize + 8 ].pack("N") + type + payload.b
    end
end
