require "test_helper"

class Documents::FileServingTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @pdf = text_pdf("Page one has words", "Page two has words")
    @document = ingest(@pdf, filename: "two.pdf")
    @document.update!(page_count: 2, status: "ready")
  end

  test "a file on the plain disk is streamed from the volume" do
    ActiveStorage::Blob.any_instance.expects(:download).never

    get document_file_path(@document)

    assert_response :success
    assert_equal @pdf, response.body
    assert_equal "bytes", response.headers["Accept-Ranges"]
  end

  test "a byte range returns only those bytes" do
    get document_file_path(@document), headers: { "Range" => "bytes=0-9" }

    assert_response :partial_content
    assert_equal @pdf.byteslice(0, 10), response.body
    assert_equal "bytes 0-9/#{@pdf.bytesize}", response.headers["Content-Range"]
  end

  test "a front server that sends files is handed the whole file to answer a range" do
    Rails.application.config.action_dispatch.stubs(:x_sendfile_header).returns("X-Sendfile")
    ActiveStorage::Blob.any_instance.expects(:download_chunk).never

    get document_file_path(@document), headers: { "Range" => "bytes=0-9" }

    assert_response :success
    assert_equal @pdf, response.body
    assert_nil response.headers["Content-Range"]
  end

  test "a private file is decrypted and served whole or by range" do
    private_pdf = text_pdf("Diagnosis page")
    document = ingest(private_pdf, filename: "private.pdf", private: true, private_reason: "Uploaded as private")

    get document_file_path(document)
    assert_equal private_pdf, response.body

    get document_file_path(document), headers: { "Range" => "bytes=5-14" }
    assert_response :partial_content
    assert_equal private_pdf.byteslice(5, 10), response.body
  end

  test "PDFs, images and plain text are shown inline in a sandbox" do
    get document_file_path(@document)
    assert_response :success
    assert_match(/\Ainline/, response.headers["Content-Disposition"])
    assert_equal "sandbox", response.headers["Content-Security-Policy"]

    thumbnail = Vips::Image.black(20, 20).write_to_buffer(".jpg")
    @document.thumbnail.attach(io: StringIO.new(thumbnail), filename: "thumbnail.jpg", content_type: "image/jpeg")
    get document_thumbnail_path(@document)
    assert_response :success
    assert_equal thumbnail, response.body
    assert_equal "image/jpeg", response.media_type
    assert_match(/\Ainline/, response.headers["Content-Disposition"])

    text = ingest("Plain words", filename: "notes.txt")
    get document_file_path(text)
    assert_match(/\Ainline/, response.headers["Content-Disposition"])
  end

  test "any other type is only downloaded, even when asked to show it" do
    %w[text/html image/svg+xml text/markdown text/csv].each do |type|
      @document.file.blob.update!(content_type: type)

      get document_file_path(@document)

      assert_response :success
      assert_match(/\Aattachment/, response.headers["Content-Disposition"], type)
      assert_equal "sandbox", response.headers["Content-Security-Policy"]
    end
  end

  test "page images are rendered once and then served from the cache" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    get document_page_path(@document, 1, size: "thumb")
    first = response.body
    stored = Rails.cache.read([ "page-image", @document.file.blob.key, 1, Documents::PagesController::EDGES["thumb"] ])
    assert_equal "\xFF\xD8\xFF".b, first.byteslice(0, 3)
    refute_includes stored.to_s.b, "\xFF\xD8\xFF".b, "the cache holds ciphertext, not the JPEG"
    assert_equal first, ActiveRecord::Encryption.encryptor.decrypt(stored).b
    Pdf.expects(:render_page).never
    get document_page_path(@document, 1, size: "thumb")

    assert_response :success
    assert_equal first, response.body
    assert_equal "image/jpeg", response.media_type
  ensure
    Rails.cache = original
  end
end
