require "test_helper"

class NativeTextTest < ActiveSupport::TestCase
  test "reads plain text" do
    with_file("Grocery list\nmilk\n", ".txt") do |path|
      assert_equal [ "Grocery list\nmilk\n" ], NativeText.extract(path, "text/plain")
    end
  end

  test "reads csv rows" do
    with_file("item,amount\nrent,1200\n", ".csv") do |path|
      text = NativeText.extract(path, "text/csv").join

      assert_includes text, "item\tamount"
      assert_includes text, "rent\t1200"
    end
  end

  test "reads Word documents" do
    with_file(docx("Lease agreement", "Monthly rent is due on the first."), ".docx") do |path|
      text = NativeText.extract(path, NativeText::WORD_TYPE).join

      assert_includes text, "Lease agreement"
      assert_includes text, "Monthly rent is due on the first."
    end
  end

  test "reads a PDF text layer page by page" do
    pdf = text_pdf("First page has plenty of words to count as real text here.", "Second page also has plenty of words to count as text.")

    pages = with_pdf_file(pdf) { |path| NativeText.extract(path, "application/pdf") }

    assert_equal 2, pages.size
    assert_includes pages.first, "First page"
  end

  test "returns nil for a scan so it goes to OCR" do
    assert_nil with_pdf_file(scanned_pdf(PdfFactory.printed)) { |path| NativeText.extract(path, "application/pdf") }
  end

  test "returns nil for images" do
    assert_nil NativeText.extract("/nonexistent.png", "image/png")
  end

  private
    def with_file(data, extension)
      Tempfile.create([ "native", extension ], binmode: true) do |file|
        file.write(data)
        file.flush
        yield file.path
      end
    end

    # A minimal Word file with the parts every real one has.
    def docx(*paragraphs)
      body = paragraphs.map { |text| "<w:p><w:r><w:t>#{text}</w:t></w:r></w:p>" }.join
      buffer = Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry("[Content_Types].xml")
        zip.write <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          </Types>
        XML
        zip.put_next_entry("_rels/.rels")
        zip.write <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
          </Relationships>
        XML
        zip.put_next_entry("word/_rels/document.xml.rels")
        zip.write %(<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>)
        zip.put_next_entry("word/styles.xml")
        zip.write %(<?xml version="1.0" encoding="UTF-8"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"/>)
        zip.put_next_entry("word/document.xml")
        zip.write %(<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>#{body}</w:body></w:document>)
      end
      buffer.string
    end
end
