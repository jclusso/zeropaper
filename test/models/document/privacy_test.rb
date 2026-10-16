require "test_helper"

# A private document never leaves the machine. These tests run the whole
# pipeline with a hosted OCR engine and an OpenAI key configured, and with
# WebMock refusing every outbound connection.
class Document::PrivacyTest < ActiveSupport::TestCase
  setup { configure_openai }

  test "a private text document is processed entirely locally" do
    document = process(ingest(BILL_TEXT, filename: "bill.txt", private: true))

    assert_equal "ready", document.status
    assert_equal "rules", document.metadata_source
    assert_equal correspondents(:acme_power), document.correspondent
    assert_equal Date.new(2026, 3, 14), document.document_date
    assert document.chunks.any?
    assert_no_external_requests
  end

  test "a private scan is read with local OCR" do
    pdf = scanned_pdf(PdfFactory.printed, PdfFactory.blank, PdfFactory.printed)
    document = process(ingest(pdf, filename: "scan.pdf", private: true))

    assert_equal "tesseract", document.text_source
    assert_equal [ 2 ], document.page_record["ocr_skipped"]
    assert_includes document.review_reasons, "blank_pages"
    assert_no_external_requests
  end

  test "private text is encrypted in the database" do
    document = process(ingest(BILL_TEXT, filename: "bill.txt", private: true))

    raw_content = Document.connection.select_value("SELECT content FROM documents WHERE id = #{document.id}")
    refute_includes raw_content, "Acme Power"
    assert_includes document.content, "Acme Power"
  end

  test "a document matching a content rule becomes private before anything is sent" do
    private_rule("Medical", field: "content", operator: "any", value: "diagnosis")
    document = process(ingest("Lab results\nDiagnosis: seasonal allergies\n", filename: "results.txt"))

    assert document.private?
    assert_equal "Matched rule “Medical”", document.private_reason
    assert_equal "rules", document.metadata_source
    assert_no_external_requests
  end

  test "a rule naming a correspondent keeps its documents private and files them" do
    document = process(ingest("Appointment reminder from City Clinic on May 2, 2026.", filename: "reminder.txt"))

    assert document.private?
    assert_equal "Matched rule “Private: City Clinic”", document.private_reason
    assert_equal correspondents(:city_clinic), document.correspondent
    assert_no_external_requests
  end

  test "a rule for a correspondent is created once" do
    clinic = correspondents(:city_clinic)
    hospital = Correspondent.create!(name: "Harbor Hospital")

    assert_no_difference -> { Rule.count } do
      Rule.privatize_mentions_of!(clinic)
    end
    rule = Rule.privatize_mentions_of!(hospital)

    assert rule.mark_private?
    assert_equal hospital, rule.correspondent
    assert_equal "Private: Harbor Hospital", rule.name
    assert rule.matches?(Document.new, text: "Discharge summary from Harbor Hospital")
    refute rule.matches?(Document.new, text: "Harbor tour tickets")
  end

  test "a scan is screened with local OCR before hosted OCR could see it" do
    private_rule("Payroll", field: "content", operator: "any", value: "payroll")
    document = process(ingest(scanned_text_pdf("PAYROLL SUMMARY\nEmployee salary report\n"), filename: "scan_0001.pdf"))

    assert document.private?, "expected local OCR to find 'payroll', got #{document.content.inspect}"
    assert_equal "tesseract", document.text_source
    assert_no_external_requests
  end

  test "a filename rule marks the document private at ingest" do
    private_rule("Tax files", field: "filename", operator: "any", value: "tax")
    document = ingest("Form 1040", filename: "2025 tax.txt")

    assert document.private?
    assert_equal "Matched rule “Tax files”", document.private_reason
  end

  test "privatize! keeps details AI already returned" do
    Setting.instance.update!(ai_enabled: false)
    document = process(ingest(BILL_TEXT, filename: "bill.txt"))
    energy = Correspondent.create!(name: "Acme Energy Group")
    document.update!(title: "Acme Electricity Bill", summary: "AI summary", document_date: Date.new(2026, 3, 1), correspondent: energy,
      tag_names: [ "Utilities" ], metadata_source: "ai", ai_model: "gpt-5.6-luna", confidence: 0.9)

    assert_enqueued_with(job: ProcessDocumentJob) { document.privatize!(reason: "Marked private by Ada") }

    document.reload
    assert document.private?
    assert_equal "AI summary", document.summary
    assert_equal "gpt-5.6-luna", document.ai_model
    assert_equal "ai", document.metadata_source
    assert_equal BILL_TEXT, document.file.download

    process(document)
    assert_equal "Acme Electricity Bill", document.title
    assert_equal "AI summary", document.summary
    assert_equal Date.new(2026, 3, 1), document.document_date
    assert_equal energy, document.correspondent
    assert_includes document.tags.map(&:name), "Utilities"
    assert_equal "ai", document.metadata_source
    assert_equal "gpt-5.6-luna", document.ai_model
    assert_no_external_requests
  end

  test "the local reprocess fills details AI left empty" do
    Setting.instance.update!(ai_enabled: false)
    document = process(ingest(BILL_TEXT, filename: "scan_0009.txt"))
    document.update!(title: "Acme Electricity Bill", document_date: nil, correspondent: nil, metadata_source: "ai")

    document.privatize!(reason: "Marked private by Ada")
    process(document)

    assert_equal "Acme Electricity Bill", document.title
    assert_equal Date.new(2026, 3, 14), document.document_date
    assert_equal correspondents(:acme_power), document.correspondent
  end

  test "making a document private during local OCR stops the run before any hosted call" do
    private_rule("Payroll", field: "content", operator: "any", value: "payroll")
    document = ingest(scanned_text_pdf("Water bill\nAmount due\n"), filename: "scan_0002.pdf")
    read = Ocr::Result.new(pages: { 1 => "Water bill\nAmount due" })
    Ocr::Tesseract.any_instance.stubs(:call).with { Document.find(document.id).privatize!(reason: "Marked private by Ada"); true }.returns(read)

    assert_enqueued_with(job: ProcessDocumentJob) { document.process! }

    document.reload
    assert document.private?
    assert_equal "pending", document.status, "the local run that privatize! queued owns the document"
    assert_nil document.content, "the stale run wrote no text"
    refute document.archive_file.attached?
    assert_no_external_requests
  end

  test "a run stops when the document's privacy changes under it, even without a newer run" do
    private_rule("Payroll", field: "content", operator: "any", value: "payroll")
    document = ingest(scanned_text_pdf("Water bill\nAmount due\n"), filename: "scan_0002.pdf")
    read = Ocr::Result.new(pages: { 1 => "Water bill\nAmount due" })
    Ocr::Tesseract.any_instance.stubs(:call).with { Document.find(document.id).privatize!(reason: "Marked private by Ada", reprocess: false); true }.returns(read)

    document.process!

    document.reload
    assert document.private?
    assert_nil document.content
    assert_nil document.error, "the run stopped instead of trying hosted OCR and failing"
    assert_nil document.step_state("metadata")["status"]
    assert_no_external_requests
  end

  test "AI details that arrive after the document went private are not saved" do
    body = YAML.load_file(Rails.root.join("test/vcr_cassettes/metadata/openai_electricity_bill.yml")).dig("http_interactions", 0, "response", "body", "string")
    document = ingest(BILL_TEXT, filename: "bill.txt")
    stub_request(:post, "https://api.openai.com/v1/responses").to_return do
      Document.where(id: document.id).update_all(private: true)
      { status: 200, headers: { "Content-Type" => "application/json" }, body: body }
    end

    document.process!

    document.reload
    assert document.private?
    assert_nil document.summary
    assert_nil document.ai_model
    assert_nil document.title
  end

  test "a mixed PDF is screened with its embedded text before hosted OCR" do
    private_rule("Payroll", field: "content", operator: "any", value: "payroll")
    pdf = PdfFactory.build([ "PAYROLL SUMMARY\nEmployee salary report for March 2026\nGross pay and deductions by employee\n", PdfFactory.printed ])
    document = process(ingest(pdf, filename: "scan_0003.pdf"))

    assert document.private?, "expected the embedded text to make it private, got #{document.content.inspect}"
    assert_match "embedded text", document.text_source
    assert_no_external_requests
  end

  test "the AI blank-page check waits while a content rule still has to read the text" do
    Setting.instance.update!(blank_page_ai_check: true)
    private_rule("Payroll", field: "content", operator: "any", value: "payroll")
    BlankPages::Detector.any_instance.stubs(:call).returns([ BlankPages::Verdict.new(blank: false, sure: true), BlankPages::Verdict.new(blank: true, sure: false) ])
    BlankPages::Judge.any_instance.expects(:call).never
    pdf = PdfFactory.build([ "PAYROLL SUMMARY\nEmployee salary report for March 2026\nGross pay and deductions by employee\n", PdfFactory.printed ])

    document = process(ingest(pdf, filename: "scan_0004.pdf"))

    refute BlankPages::Judge.available_for?(Document.new)
    assert document.private?
    assert_match "AI check skipped", document.step_state("blank_pages")["detail"]
    assert_no_external_requests
  end

  test "the AI blank-page check is offered when no content rule could make the document private" do
    Setting.instance.update!(blank_page_ai_check: true)
    Rule.where(mark_private: true).delete_all

    assert BlankPages::Judge.available_for?(Document.new)
  end

  test "filename rules added after ingest run before processing reads anything" do
    document = ingest("Form 1040", filename: "2025 tax.txt")
    private_rule("Tax files", field: "filename", operator: "any", value: "tax")

    process(document)

    assert document.private?
    assert_equal "Matched rule “Tax files”", document.private_reason
    assert_equal "rules", document.metadata_source
    assert_no_external_requests
  end

  test "a private copy of a stored document makes the stored one private" do
    document = ingest(BILL_TEXT, filename: "bill.txt")

    error = assert_raises(Document::Duplicate) do
      Document.ingest!(io: StringIO.new(BILL_TEXT), filename: "copy.txt", source: "folder", private: true, private_reason: "Added from the private folder")
    end

    assert_equal document, error.document
    document.reload
    assert document.private?
    assert_equal "Added from the private folder", document.private_reason
  end

  test "a shareable copy of a stored document changes nothing" do
    document = ingest(BILL_TEXT, filename: "bill.txt", private: true)

    assert_raises(Document::Duplicate) { Document.ingest!(io: StringIO.new(BILL_TEXT), filename: "copy.txt", source: "upload") }

    assert document.reload.private?
  end

  test "making a document not private is refused while a filename rule still marks it private" do
    private_rule("Tax files", field: "filename", operator: "any", value: "tax")
    document = ingest("Form 1040", filename: "2025 tax.txt")

    assert_no_enqueued_jobs(only: ProcessDocumentJob) do
      refute document.publicize!
    end

    assert document.reload.private?
    assert_match "“Tax files” still marks this document private", document.errors.full_messages.to_sentence
  end

  test "publicize! queues normal processing" do
    document = process(ingest(BILL_TEXT, filename: "bill.txt", private: true))

    assert_enqueued_with(job: ProcessDocumentJob) { document.publicize! }

    document.reload
    refute document.private?
    assert_nil document.private_reason
    assert_equal BILL_TEXT, document.file.download
  end

  private
    def private_rule(name, field:, operator:, value:)
      Rule.create!(name: name, conditions: [ { field: field, operator: operator, value: value } ], mark_private: true)
    end
end
