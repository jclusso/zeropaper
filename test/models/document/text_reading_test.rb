require "test_helper"

class Document::TextReadingTest < ActiveSupport::TestCase
  test "a born-digital PDF keeps its embedded text without OCR" do
    document = process(ingest(text_pdf("Acme Power statement for March 2026 with the amount due of $87.40 by April 1"), filename: "statement.pdf"))

    assert_equal "native", document.text_source
    assert_match "amount due of $87.40", document.content
    refute document.archive_file.attached?
  end

  test "a scanner's own OCR layer is replaced by reading the page again" do
    pages = NativeText.pdf_pages(fixture_path(scan_with_ocr_layer))
    assert pages.first.scanned
    refute pages.first.trusted?

    Setting.instance.update!(searchable_pdf: true)
    document = process(ingest(scan_with_ocr_layer, filename: "scan_0003.pdf"))
    assert_equal "tesseract", document.text_source
    assert_match(/payroll/i, document.content)
    assert document.archive_file.attached?
  end

  test "a mixed PDF reads only its scanned pages" do
    mixed = combine(text_pdf("Cover letter from Acme Power about the March statement and amount due"), scanned_text_pdf("PAYROLL SUMMARY\nEmployee salary report\n"))
    document = process(ingest(mixed, filename: "mixed.pdf"))

    assert_equal "tesseract + embedded text", document.text_source
    assert_equal "Tesseract (local) + embedded text", document.send(:text_source_label)
    first, second = document.page_texts
    assert_match "Cover letter from Acme Power", first
    assert_match(/payroll/i, second)
  end

  test "garbage text layers do not count as text" do
    refute NativeText.readable?("Ã¢â‚¬Å“ Ã¢â‚¬Â Ã¢â‚¬â€ Ã‚Â© Ã¢â€žÂ¢ Ã¢â‚¬Â¦ Ã¢â‚¬Å“ Ã¢â‚¬Â Ã¢â‚¬â€")
    refute NativeText.readable?("(cid:12)(cid:13)(cid:14)(cid:15) appears where fonts lack a map")
    refute NativeText.readable?("xkcd brtz qwfp zxcv bnmlk hjkl tyrw prst vbnm cvbn")
    assert NativeText.readable?("Acme Power statement for March 2026, amount due $87.40")
  end

  test "scans are read by the vision model's OCR API when it is an OCR model" do
    mistral = AIProvider.create!(kind: "mistral", api_key: TestKeys::MISTRAL)
    configure_openai(vision_provider: mistral, vision_model: "mistral-ocr-latest", searchable_pdf: false)
    document = ingest(scanned_text_pdf("PAYROLL SUMMARY\nEmployee salary report\n"), filename: "scan_0004.pdf")

    VCR.use_cassette("ocr/mistral_ocr") do
      VCR.use_cassette("metadata/openai_electricity_bill") { process(document) }
    end

    assert_equal "Mistral · mistral-ocr-latest", document.text_source
    assert_match "Employee salary report for March 2026", document.content
    assert_requested :post, "https://api.mistral.ai/v1/ocr"
  end

  test "when the vision model fails, the local engine reads the scan" do
    configure_openai(searchable_pdf: false)
    document = ingest(scanned_text_pdf("PAYROLL SUMMARY\nEmployee salary report\n"), filename: "scan_0005.pdf")

    VCR.use_cassette("ocr/openai_vision_outage", allow_playback_repeats: true) do
      document.process!(extract_metadata: false)
    end
    document.reload

    assert_equal "ready", document.status
    assert_equal "tesseract", document.text_source
    assert_match(/payroll/i, document.content)
    assert_match "AI could not read it", document.step_state("text")["detail"]
  end

  test "the searchable PDF is built while the AI model reads the scan" do
    mistral = AIProvider.create!(kind: "mistral", api_key: TestKeys::MISTRAL)
    configure_openai(vision_provider: mistral, vision_model: "mistral-ocr-latest", searchable_pdf: true)
    document = ingest(scanned_text_pdf("PAYROLL SUMMARY\nEmployee salary report\n"), filename: "scan_0008.pdf")

    VCR.use_cassette("ocr/mistral_ocr") do
      VCR.use_cassette("metadata/openai_electricity_bill") { process(document) }
    end

    assert_equal "Mistral · mistral-ocr-latest", document.text_source
    assert_match "Employee salary report for March 2026", document.content
    assert document.archive_file.attached?, "the searchable PDF from the parallel Tesseract run is kept"
  end

  test "when the AI model fails, the Tesseract run already underway supplies the text" do
    configure_openai(searchable_pdf: true)
    document = ingest(scanned_text_pdf("PAYROLL SUMMARY\nEmployee salary report\n"), filename: "scan_0009.pdf")
    Ocr::Tesseract.any_instance.expects(:call).once.returns(Ocr::Result.new(pages: { 1 => "PAYROLL SUMMARY from tesseract" }))

    VCR.use_cassette("ocr/openai_vision_outage", allow_playback_repeats: true) do
      document.process!(extract_metadata: false)
    end
    document.reload

    assert_equal "tesseract", document.text_source
    assert_match "PAYROLL SUMMARY from tesseract", document.content
  end

  private
    def scan_with_ocr_layer
      @scan_with_ocr_layer ||= with_pdf_file(scanned_text_pdf("PAYROLL SUMMARY\nEmployee salary report\n")) do |path|
        output = "#{path}.ocr.pdf"
        system("ocrmypdf", "-q", path, output, exception: true)
        File.binread(output).tap { FileUtils.rm_f(output) }
      end
    end

    def combine(*pdfs)
      Dir.mktmpdir do |dir|
        paths = pdfs.each_with_index.map { |data, index| File.join(dir, "#{index}.pdf").tap { |path| File.binwrite(path, data) } }
        output = File.join(dir, "combined.pdf")
        system("qpdf", "--empty", "--pages", *paths, "--", output, exception: true)
        File.binread(output)
      end
    end

    def fixture_path(data)
      file = Tempfile.new([ "page", ".pdf" ])
      file.binmode
      file.write(data)
      file.close
      (@tempfiles ||= []) << file
      file.path
    end
end
