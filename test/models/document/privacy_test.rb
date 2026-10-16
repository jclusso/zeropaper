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
    assert_no_hosted_ai_requests
  end

  test "a private scan is read with local OCR" do
    pdf = scanned_pdf(PdfFactory.printed, PdfFactory.blank, PdfFactory.printed)
    document = process(ingest(pdf, filename: "scan.pdf", private: true))

    assert_equal "tesseract", document.text_source
    assert_equal [ 2 ], document.page_record["ocr_skipped"]
    assert_includes document.review_reasons, "blank_pages"
    assert_no_hosted_ai_requests
  end

  test "private files are stored encrypted and their text is encrypted in the database" do
    document = process(ingest(BILL_TEXT, filename: "bill.txt", private: true))

    assert_equal "test_private", document.file.blob.service_name
    refute_includes stored_bytes(document.file), "Acme Power"

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
    assert_equal "test_private", document.file.blob.service_name
    assert_no_hosted_ai_requests
  end

  test "a rule naming a correspondent keeps its documents private and files them" do
    document = process(ingest("Appointment reminder from City Clinic on May 2, 2026.", filename: "reminder.txt"))

    assert document.private?
    assert_equal "Matched rule “Private: City Clinic”", document.private_reason
    assert_equal correspondents(:city_clinic), document.correspondent
    assert_no_hosted_ai_requests
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
    assert_no_hosted_ai_requests
  end

  test "a filename rule marks the document private at ingest" do
    private_rule("Tax files", field: "filename", operator: "any", value: "tax")
    document = ingest("Form 1040", filename: "2025 tax.txt")

    assert document.private?
    assert_equal "Matched rule “Tax files”", document.private_reason
    assert_equal "test_private", document.file.blob.service_name
  end

  test "privatize! moves files to encrypted storage and drops AI details" do
    Setting.instance.update!(ai_enabled: false)
    document = process(ingest(BILL_TEXT, filename: "bill.txt"))
    document.update!(summary: "AI summary", metadata_source: "ai", ai_model: "gpt-5.6-luna")
    assert_equal "test", document.file.blob.service_name

    assert_enqueued_with(job: ProcessDocumentJob) { document.privatize!(reason: "Marked private by Ada") }

    document.reload
    assert document.private?
    assert_equal "test_private", document.file.blob.service_name
    assert_equal "test_private", document.thumbnail.blob.service_name if document.thumbnail.attached?
    assert_nil document.summary
    assert_nil document.ai_model
    assert_equal BILL_TEXT, document.file.download
  end

  test "publicize! moves files back and queues normal processing" do
    document = process(ingest(BILL_TEXT, filename: "bill.txt", private: true))

    assert_enqueued_with(job: ProcessDocumentJob) { document.publicize! }

    document.reload
    refute document.private?
    assert_nil document.private_reason
    assert_equal "test", document.file.blob.service_name
    assert_equal BILL_TEXT, document.file.download
  end

  private
    def private_rule(name, field:, operator:, value:)
      Rule.create!(name: name, conditions: [ { field: field, operator: operator, value: value } ], mark_private: true)
    end
end
