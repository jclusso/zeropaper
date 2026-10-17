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
    %w[
      http://8.8.8.8:5001 https://docling.example.com http://[2001:4860:4860::8888]:5001 ftp://docling:21 not-a-url
      http://134744072:5001 http://0x08080808:5001 http://100.101.102.103:5001 http://100.128.0.1:5001
    ].each do |url|
      refute @setting.update(local_ocr_provider: "docling", docling_url: url), "#{url} should be refused"
      assert_includes @setting.errors[:docling_url], "must be on this machine or the local network, such as http://zeropaper-docling:5001"
    end
  end

  test "a DOCLING_URL that is not local is ignored" do
    LocalNetwork.stubs(:resolve).with("docling.example.com").returns([ "93.184.215.14" ])
    LocalNetwork.stubs(:resolve).with("docling").returns([ "172.18.0.4" ])

    %w[https://docling.example.com http://8.8.8.8:5001 ftp://docling:21].each do |url|
      with_env("DOCLING_URL" => url) do
        assert_equal({ local_ocr_provider: "tesseract" }, Setting.from_environment, url)
      end
    end
    with_env("DOCLING_URL" => "http://docling:5001") do
      assert_equal({ docling_url: "http://docling:5001", local_ocr_provider: "docling" }, Setting.from_environment)
    end
  end

  test "a DOCLING_URL whose host does not resolve yet is kept and checked for each document" do
    Setting.delete_all
    LocalNetwork.stubs(:resolve).with("docling").returns([])

    setting = with_env("DOCLING_URL" => "http://docling:5001") { Setting.instance }

    assert_equal "http://docling:5001", setting.docling_url
    assert_equal "docling", setting.local_ocr_provider
    assert_equal "tesseract", setting.local_ocr_engine

    LocalNetwork.stubs(:resolve).with("docling").returns([ "172.18.0.4" ])
    assert_equal "docling", setting.local_ocr_engine
  end

  test "a single-label name is resolved like any other" do
    LocalNetwork.stubs(:resolve).with("docling").returns([ "172.18.0.4", "8.8.8.8" ])

    refute @setting.update(local_ocr_provider: "docling", docling_url: "http://docling:5001")
    assert_includes @setting.errors[:docling_url], "must be on this machine or the local network, such as http://zeropaper-docling:5001"
  end

  test "every document falls back to Tesseract when Docling is no longer local" do
    @setting.update_columns(local_ocr_provider: "docling", docling_url: "http://8.8.8.8:5001")
    assert_equal "tesseract", @setting.local_ocr_engine

    @setting.update_columns(docling_url: "http://zeropaper-docling:5001")
    assert_equal "docling", @setting.local_ocr_engine
  end

  test "Docling refuses to send any document to a host that is not local" do
    @setting.update_columns(local_ocr_provider: "docling", docling_url: "http://docling:5001")
    LocalNetwork.stubs(:resolve).with("docling").returns([ "8.8.8.8" ])

    with_pdf_file(text_pdf("Water bill")) do |path|
      assert_raises(Ocr::Docling::NotLocalError) { Ocr::Docling.new(@setting).call(path, pages: [ 1 ], content_type: "application/pdf") }
    end
    assert_no_external_requests
  end

  test "Docling requests connect to the local addresses that were checked" do
    @setting.update_columns(local_ocr_provider: "docling", docling_url: "http://docling:5001")
    sent = nil
    response = stub(raise_for_status: nil, json: { "status" => "success", "document" => { "md_content" => "Water bill" } })
    HttpRequest.stubs(:post).with { |url, addresses:, **| sent = [ url, addresses ] }.returns(response)

    result = with_pdf_file(text_pdf("Water bill")) { |path| Ocr::Docling.new(@setting).call(path, pages: [ 1 ], content_type: "application/pdf") }

    assert_equal "Water bill", result.pages[1]
    assert_equal [ "http://docling:5001/v1/convert/file", [ "172.18.0.4" ] ], sent
  end

  test "a pinned request does not resolve the host again" do
    client = stub(post: :response)
    HTTPX.stubs(:with).with { |options| options[:addresses] == { "docling" => [ "172.18.0.4" ] } }.returns(client)

    assert_equal :response, HttpRequest.post("http://docling:5001/v1/convert/file", form: {}, addresses: [ "172.18.0.4" ])
  end

  test "a shareable scan is read with Tesseract when Docling is not local" do
    @setting.update_columns(local_ocr_provider: "docling", docling_url: "http://8.8.8.8:5001")

    document = process(ingest(scanned_text_pdf("Water bill\nAmount due\n"), filename: "scan_0008.pdf"))

    refute document.private?
    assert_equal "tesseract", document.text_source
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
