module DocumentHelpers
  def fixture_file(name)
    Rails.root.join("test/fixtures/files", name)
  end

  # Ingests without running the pipeline job, so tests call process! themselves.
  def ingest(data, filename:, **options)
    document = nil
    assert_enqueued_with(job: ProcessDocumentJob) do
      document = Document.ingest!(io: StringIO.new(data), filename: filename, source: options.delete(:source) || "upload", **options)
    end
    document
  end

  def process(document, **options)
    document.process!(**options)
    document.reload
    assert_nil document.error, "processing failed: #{document.error}"
    document
  end

  # An OpenAI provider assigned to every task, as the setup wizard leaves it.
  def configure_openai(**settings)
    openai = AIProvider.create!(kind: "openai", api_key: TestKeys::OPENAI)
    Setting.instance.update!(
      ai_enabled: true,
      extraction_provider: openai, extraction_model: "gpt-5.6-luna",
      research_provider: openai, research_model: "gpt-5.6",
      vision_provider: openai, vision_model: "gpt-5.6-luna",
      **settings
    )
    openai
  end
end

module DocumentHelpers
  BILL_TEXT = <<~TEXT.freeze
    Acme Power
    Electricity statement
    Statement date: March 14, 2026
    You used 412 kWh this month.
    Amount due: $87.40 by 04/01/2026
    Account 55-0192
  TEXT

  # A form filled in from one template, so reports for different cars read
  # alike apart from their numbers.
  INSPECTION_REPORT = <<~TEXT.freeze
    State of New York Vehicle Inspection Program
    VEHICLE INSPECTION REPORT
    Inspection Date: %<date>s  Expiration Date: %<expires>s
    Vehicle make BMW model %<model>s VIN %<vin>s odometer %<miles>s
    Station facility number 7M41 inspector certified emissions passed safety passed
    Brakes passed lights passed tires passed steering passed horn passed wipers passed
  TEXT

  LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

  # A saved document with text but no file, for testing rules and indexing.
  def document_with_text(content, filename: "notes.txt", **attributes)
    Document.create!(original_filename: filename, content_type: "text/plain", checksum: SecureRandom.hex(32), content: content, status: "ready", **attributes)
  end

  # Renders text to a grayscale image and wraps it as a scan with no text
  # layer, so only OCR can read it.
  def scanned_text_pdf(text)
    with_pdf_file(text_pdf(text)) do |path|
      Dir.mktmpdir do |dir|
        system("pdftoppm", "-gray", "-r", "200", "-singlefile", path, File.join(dir, "page"), exception: true)
        image = BlankPages::Gray.read(File.join(dir, "page.pgm"))
        canvas = PdfFactory::Canvas.new(image.width, image.height)
        canvas.pixels.replace(image.pixels)
        scanned_pdf(canvas)
      end
    end
  end

  # Fails when the test made any request to a host other than this machine,
  # stubbed or not.
  def assert_no_external_requests
    hosts = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.map { |request| request.uri.host.delete_prefix("[").delete_suffix("]") }
    external = hosts.uniq - LOCAL_HOSTS
    assert_empty external, "expected no requests beyond this machine, but #{external.to_sentence} #{external.one? ? "was" : "were"} called"
  end
end
