require "test_helper"

class SettingDoclingTest < ActiveSupport::TestCase
  setup { @setting = Setting.instance }

  test "Docling on this machine or the local network is accepted" do
    %w[
      http://zeropaper-docling:5001 http://docling:5001 http://localhost:5001 http://127.0.0.1:5001
      http://[::1]:5001 http://10.0.0.3:5001 http://172.18.0.4:5001 http://192.168.1.20:5001
    ].each do |url|
      assert @setting.update(local_ocr_provider: "docling", docling_url: url), "#{url}: #{@setting.errors.full_messages.to_sentence}"
    end
  end

  test "Docling anywhere else is refused" do
    %w[http://8.8.8.8:5001 https://docling.example.com http://[2001:4860:4860::8888]:5001 ftp://docling:21 not-a-url].each do |url|
      refute @setting.update(local_ocr_provider: "docling", docling_url: url), "#{url} should be refused"
      assert_includes @setting.errors[:docling_url], "must be on this machine or the local network, such as http://zeropaper-docling:5001"
    end
  end

  test "a DOCLING_URL that is not local is ignored" do
    with_env("DOCLING_URL" => "https://docling.example.com") do
      assert_equal({ local_ocr_provider: "tesseract" }, Setting.from_environment)
    end
    with_env("DOCLING_URL" => "http://docling:5001") do
      assert_equal({ docling_url: "http://docling:5001", local_ocr_provider: "docling" }, Setting.from_environment)
    end
  end

  test "private documents fall back to Tesseract when Docling is no longer local" do
    @setting.update_columns(local_ocr_provider: "docling", docling_url: "http://8.8.8.8:5001")
    secret = document_with_text("Diagnosis", private: true)
    shareable = document_with_text("Bill")

    assert_equal "tesseract", @setting.local_ocr_provider_for(secret)
    assert_equal "docling", @setting.local_ocr_provider_for(shareable)

    @setting.update_columns(docling_url: "http://zeropaper-docling:5001")
    assert_equal "docling", @setting.local_ocr_provider_for(secret)
  end

  test "Docling refuses to send a private document to a host that is not local" do
    @setting.update_columns(local_ocr_provider: "docling", docling_url: "http://8.8.8.8:5001")
    secret = document_with_text("Diagnosis", private: true)

    with_pdf_file(text_pdf("Diagnosis")) do |path|
      assert_raises(Ocr::Docling::NotLocalError) { Ocr::Docling.new(@setting, secret).call(path, pages: [ 1 ], content_type: "application/pdf") }
    end
    assert_no_external_requests
  end

  test "a private scan is read with Tesseract when Docling is not local" do
    @setting.update_columns(local_ocr_provider: "docling", docling_url: "http://8.8.8.8:5001")

    document = process(ingest(scanned_text_pdf("Lab results\nAll values normal\n"), filename: "scan_0005.pdf", private: true))

    assert_equal "tesseract", document.text_source
    assert_no_external_requests
  end

  private
    def with_env(values)
      previous = values.keys.to_h { |key| [ key, ENV[key] ] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| ENV[key] = value }
    end
end
