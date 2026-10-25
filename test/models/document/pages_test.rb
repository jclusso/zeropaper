require "test_helper"

class Document::PagesTest < ActiveSupport::TestCase
  setup do
    @pdf = scanned_pdf(PdfFactory.printed, PdfFactory.blank, PdfFactory.printed)
    @document = process(ingest(@pdf, filename: "scan.pdf"))
  end

  test "processing records the blank page and skips it in OCR" do
    assert_equal 3, @document.page_count
    assert_equal [ 2 ], @document.suggested_blank_pages
    assert_equal [ 2 ], @document.page_record["ocr_skipped"]
    assert_equal [ 1, 3 ], @document.pages_to_read
    assert_includes @document.review_reasons, "blank_pages"
  end

  test "removing a page OCR skipped keeps the text and does not reprocess" do
    original_checksum = @document.checksum

    assert_no_enqueued_jobs(only: ProcessDocumentJob) { @document.remove_pages!([ 2 ]) }

    @document.reload
    assert_equal 2, @document.page_count
    assert_equal [ 1, 3 ], @document.page_map
    assert_empty @document.suggested_blank_pages
    refute_equal original_checksum, @document.checksum
    assert @document.original_file.attached?
    assert_equal @pdf, @document.original_file.download
    @document.with_file_copy { |path| assert_equal 2, Pdf.page_count(path) }
    refute_includes @document.review_reasons, "blank_pages"
  end

  test "removing the first page takes the thumbnail from the searchable PDF" do
    archive = text_pdf("FIRST PAGE", "SECOND PAGE", "THIRD PAGE")
    @document.update!(archive_file: { io: StringIO.new(archive), filename: "scan.pdf", content_type: "application/pdf" })
    expected = with_pdf_file(archive) { |path| Pdf.render_page(path, 2, edge: 640, format: :jpeg) }

    @document.remove_pages!([ 1 ])

    assert_equal expected, @document.reload.thumbnail.download
  end

  test "removing a page that was read queues OCR again without new details" do
    assert_enqueued_with(job: ProcessDocumentJob, args: [ @document, { extract_metadata: false } ]) do
      @document.remove_pages!([ 1 ])
    end

    assert_equal [ 2, 3 ], @document.reload.page_map
  end

  test "keeping a page found blank confirms it and reads it" do
    assert_enqueued_with(job: ProcessDocumentJob) { @document.remove_pages!([], keep_blank: [ 2 ]) }

    @document.reload
    assert_equal [ 2 ], @document.page_record["confirmed"]
    assert_empty @document.suggested_blank_pages
    assert_equal 3, @document.page_count
  end

  test "page numbers stay tied to the original after earlier pages go" do
    @document.remove_pages!([ 1 ])
    @document.reload

    assert_equal 2, @document.original_page_number(1)
    assert_equal 1, @document.current_page_number(2)
    assert_equal [ 1 ], @document.suggested_blank_pages
  end

  test "refuses to remove every page" do
    assert_raises(Document::Pages::EditRefused) { @document.remove_pages!([ 1, 2, 3 ]) }
    assert_equal 3, @document.reload.page_count
  end

  test "refuses while the document is processing" do
    @document.update!(status: "processing")

    assert_raises(Document::Pages::EditRefused) { @document.remove_pages!([ 2 ]) }
  end

  test "restore_original! brings the upload back" do
    original_checksum = @document.checksum
    @document.remove_pages!([ 2 ])

    assert_enqueued_with(job: ProcessDocumentJob) { @document.reload.restore_original! }

    @document.reload
    assert_equal original_checksum, @document.checksum
    assert_equal @pdf, @document.file.download
    assert_equal 3, @document.page_count, "the page rail needs the count before processing finishes"
    refute @document.original_file.attached?
  end

  test "restore_original! works when another document is the same file" do
    original_checksum = @document.checksum
    @document.remove_pages!([ 2 ])
    copy = document_with_text("Same upload", title: "Full scan")
    copy.update_columns(checksum: original_checksum)

    @document.reload.restore_original!

    assert_equal original_checksum, @document.reload.checksum
    assert_equal 2, Document.where(checksum: original_checksum).count
  end

  test "restore_original! needs an original" do
    assert_raises(Document::Pages::EditRefused) { @document.restore_original! }
  end

  test "removing a skipped blank page drops its text and renumbers the passages after it" do
    pdf = PdfFactory.build([ "Alpha opening page about the lease", PdfFactory.blank, "Gamma closing page about the deposit" ])
    document = process(ingest(pdf, filename: "lease.pdf"))
    assert_equal [ 2 ], document.page_record["ocr_skipped"]
    assert_equal 3, document.page_texts.size

    assert_no_enqueued_jobs(only: ProcessDocumentJob) { document.remove_pages!([ 2 ]) }

    document.reload
    assert_equal 2, document.page_texts.size
    assert_match "Gamma", document.page_texts.last
    gamma = document.chunks.find { |chunk| chunk.content.include?("Gamma") }
    assert_equal 2, gamma.page_number
    assert_equal [ 1, 2 ], document.chunks.map(&:page_number).uniq.sort
  end

  test "a page edit that fails partway leaves the files and details as they were" do
    @document.update!(archive_file: { io: StringIO.new(@pdf), filename: "scan.pdf", content_type: "application/pdf" })
    checksum, file_blob, archive_blob = @document.checksum, @document.file.blob, @document.archive_file.blob
    Pdf.stubs(:render_page).raises(Pdf::CommandFailed, "pdftoppm crashed")

    assert_raises(Pdf::CommandFailed) { @document.remove_pages!([ 1 ]) }

    @document.reload
    assert_equal checksum, @document.checksum
    assert_equal 3, @document.page_count
    assert_equal file_blob, @document.file.blob
    assert_equal archive_blob, @document.archive_file.blob
    refute @document.original_file.attached?
  end

  test "a storage failure while saving the new pages leaves the document as it was" do
    @document.update!(archive_file: { io: StringIO.new(@pdf), filename: "scan.pdf", content_type: "application/pdf" })
    checksum, file_blob, archive_blob = @document.checksum, @document.file.blob, @document.archive_file.blob
    blobs = ActiveStorage::Blob.count
    # Attachments used to upload after the commit, so a full disk left the
    # document pointing at files that were never written.
    ActiveStorage::Service::DiskService.any_instance.stubs(:upload).raises(Errno::ENOSPC)

    assert_raises(Errno::ENOSPC) { @document.remove_pages!([ 2 ]) }
    ActiveStorage::Service::DiskService.any_instance.unstub(:upload)

    @document.reload
    assert_equal checksum, @document.checksum
    assert_equal 3, @document.page_count
    assert_equal file_blob, @document.file.blob
    assert_equal archive_blob, @document.archive_file.blob
    assert_equal @pdf, @document.file.download
    refute @document.original_file.attached?
    assert_equal blobs, ActiveStorage::Blob.count, "files stored for the failed edit are removed"
  end

  test "an edit made while another one changed the file is refused and leaves no files behind" do
    blobs = ActiveStorage::Blob.count
    other = Document.find(@document.id)
    @document.stubs(:trimmed_archive).with { other.remove_pages!([ 2 ]); true }.returns(nil)

    assert_raises(Document::Pages::EditRefused) { @document.remove_pages!([ 1 ]) }

    other.reload
    assert_equal [ 1, 3 ], other.page_map
    assert_equal 2, other.page_count
    other.with_file_copy { |path| assert_equal 2, Pdf.page_count(path) }
    # The other edit stored only the trimmed file and kept the upload, which
    # the refused edit had also chosen as its original and must not delete.
    assert_equal blobs + 1, ActiveStorage::Blob.count
    assert_equal @pdf, other.original_file.download
  end

  test "an edit chosen against an older file is refused" do
    shown = @document.checksum
    @document.remove_pages!([ 2 ])

    assert_raises(Document::Pages::EditRefused) { @document.reload.remove_pages!([ 1 ], version: shown) }
    assert_raises(Document::Pages::EditRefused) { @document.restore_original!(version: shown) }
    assert_equal 2, @document.reload.page_count
  end

  test "a page edit made before the search model downloads waits for it instead of being read again" do
    Embedder.stubs(:downloaded?).returns(false)
    Embedder.stubs(:embed_documents).raises(Embedder::ModelMissing, "still downloading")

    assert_no_enqueued_jobs(only: [ ProcessDocumentJob, IndexDocumentJob ]) { @document.remove_pages!([ 2 ]) }

    @document.reload
    assert_equal 2, @document.page_count
    assert_equal "ready", @document.status
    assert_equal "waiting", @document.step_state("index")["status"]
    stale = @document.chunks.ids

    Embedder.unstub(:embed_documents)
    Embedder.stubs(:downloaded?).returns(true)
    perform_enqueued_jobs(only: IndexDocumentJob) { DownloadEmbeddingModelJob.perform_now }

    @document.reload
    assert_equal "done", @document.step_state("index")["status"]
    assert @document.chunks.any?
    assert_empty @document.chunks.ids & stale
  end

  test "a page edit whose index fails for another reason is indexed again on its own, not read again" do
    Embedder.stubs(:embed_documents).raises(RuntimeError, "out of memory")

    assert_no_enqueued_jobs(only: ProcessDocumentJob) do
      assert_enqueued_with(job: IndexDocumentJob, args: [ @document ]) { @document.remove_pages!([ 2 ]) }
    end

    @document.reload
    assert_equal 2, @document.page_count
    assert_equal "ready", @document.status
    assert_equal "failed", @document.step_state("index")["status"]
  end

  test "the first page edit keeps the stored upload as the original instead of storing it twice" do
    upload = @document.file.blob
    blobs = ActiveStorage::Blob.count

    @document.remove_pages!([ 2 ])
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)

    @document.reload
    assert_equal upload, @document.original_file.blob
    assert_equal @pdf, @document.original_file.download
    # Only the trimmed file is new.
    assert_equal blobs + 1, ActiveStorage::Blob.count
  end

  test "a stored file whose blob row cannot be saved is deleted" do
    key = "failedsave#{SecureRandom.hex(12)}"
    ActiveStorage::Blob.stubs(:generate_unique_secure_token).returns(key)
    ActiveStorage::Blob.any_instance.stubs(:save!).with { ActiveStorage::Blob.service.exist?(key) }.raises(ActiveRecord::RecordInvalid)

    assert_raises(ActiveRecord::RecordInvalid) { @document.remove_pages!([ 2 ]) }

    assert_equal 3, @document.reload.page_count
    refute ActiveStorage::Blob.service.exist?(key)
  end

  test "restore_original! reuses the stored upload instead of uploading it again" do
    @document.remove_pages!([ 2 ])
    original_blob = @document.reload.original_file.blob
    ActiveStorage::Service::DiskService.any_instance.expects(:upload).never

    @document.restore_original!

    @document.reload
    assert_equal original_blob, @document.file.blob
    assert_equal @pdf, @document.file.download
    refute @document.original_file.attached?
  end

  test "restore_original! drops the searchable PDF made from the edited pages" do
    @document.remove_pages!([ 2 ])
    @document.reload.update!(archive_file: { io: StringIO.new(@pdf), filename: "scan.pdf", content_type: "application/pdf" })

    @document.restore_original!

    refute @document.reload.archive_file.attached?
    assert_equal @pdf, @document.viewable_pdf.download
  end
end
