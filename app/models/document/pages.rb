# Keeps a record of a PDF's pages, numbered by page of the original upload so
# blank-page findings stay attached to the right sheet after pages are
# removed. page_record holds:
#
#   map          original page number of each current page, in order
#   blank        pages found blank (local check, or the AI check when unsure)
#   unsure       blank verdicts the local check could not settle
#   ocr_skipped  pages left out of the last OCR run
#   confirmed    pages someone chose to keep despite looking blank
module Document::Pages
  extend ActiveSupport::Concern

  class EditRefused < StandardError; end

  STALE_EDIT = "This document changed since you opened it. Reload it and try again.".freeze

  def page_map
    page_record.fetch("map") { (1..page_count.to_i).to_a }
  end

  def original_page_number(current_page)
    page_map[current_page - 1]
  end

  def current_page_number(original_page)
    index = page_map.index(original_page)
    index && index + 1
  end

  # Pages, in current numbering, found blank and not confirmed as kept.
  def suggested_blank_pages
    (page_record.fetch("blank", []) - page_record.fetch("confirmed", [])).filter_map { |page| current_page_number(page) }.sort
  end

  def blank_page?(current_page)
    suggested_blank_pages.include?(current_page)
  end

  # Pages to send to OCR, in current numbering.
  def pages_to_read
    (1..page_count.to_i).to_a - suggested_blank_pages
  end

  def record_blank_pages(verdicts)
    blank = verdicts.each_with_index.filter_map { |verdict, index| original_page_number(index + 1) if verdict.blank }
    unsure = verdicts.each_with_index.filter_map { |verdict, index| original_page_number(index + 1) unless verdict.sure }
    update!(page_record: page_record.merge("map" => page_map, "blank" => blank, "unsure" => unsure))
  end

  def record_ocr_skipped(current_pages)
    update!(page_record: page_record.merge("map" => page_map, "ocr_skipped" => current_pages.map { |page| original_page_number(page) }))
  end

  # A JPEG of one page of source (an attached PDF), rendered once per file,
  # page and size rather than on every request.
  def page_image(source, page, edge:)
    SealedCache.fetch([ "page-image", source.blob.key, page, edge ], expires_in: 1.week) do
      source.open { |copy| Pdf.render_page(copy.path, page, edge: edge, format: :jpeg) }
    end
  end

  # Hashes of every page of source (the file, or the upload pages were
  # removed from), blank or not, for pairing its pages with another
  # document's. page_hashes leaves blank pages out.
  def page_fingerprints(source = file)
    return [] unless pdf? && source.attached?

    SealedCache.fetch([ "page-hashes", source.blob.key ], expires_in: 1.week) do
      source.open { |copy| PageHash.pdf_pages(copy.path) }.join(" ")
    end.split
  end

  # Whether the Pages dialog has something to offer: pages to remove, or an
  # upload to restore after pages were removed down to one.
  def reviewable_pages?
    pdf? && (page_count.to_i > 1 || original_file.attached?)
  end

  # The checksum of the file as uploaded, before pages were removed or
  # turned upright.
  def upload_checksum
    return checksum unless original_file.attached?

    SealedCache.fetch([ "checksum", original_file.blob.key ], expires_in: 1.week) do
      original_file.blob.open { |copy| Digest::SHA256.file(copy.path).hexdigest }
    end
  end

  # The viewable PDF with only pages (current numbering), so a comparison
  # can leave out pages that would put the two documents out of line.
  def viewable_pdf_with(pages)
    pdf = viewable_pdf
    data = SealedCache.fetch([ "viewable-pages", pdf.blob.key, pages.join(",") ], expires_in: 1.day) do
      pdf.open do |copy|
        Dir.mktmpdir do |dir|
          output = File.join(dir, "pages.pdf")
          Pdf.only_pages(copy.path, pages, output)
          Base64.strict_encode64(File.binread(output))
        end
      end
    end
    Base64.strict_decode64(data)
  end

  def editable_pages?
    pdf? && file.attached? && !status.in?(%w[pending processing])
  end

  # Removes pages (current numbering). The upload is kept in original_file
  # so it can be restored. OCR runs again only when the text no longer
  # matches the pages: removing pages OCR skipped drops their (empty) text
  # and reindexes locally, while removing a page that was read or keeping
  # one that was skipped reads the document again. version is the checksum
  # the edit was chosen against; an edit made against an older file is
  # refused.
  def remove_pages!(pages, keep_blank: [], version: checksum)
    raise EditRefused, "This document is still processing." unless editable_pages?
    raise EditRefused, STALE_EDIT unless version == checksum

    pages = pages.map(&:to_i).uniq.sort & (1..page_count).to_a
    raise EditRefused, "A document needs at least one page." if pages.size >= page_count

    removed = pages.map { |page| original_page_number(page) }
    confirmed = keep_blank.map { |page| original_page_number(page.to_i) }.compact
    skipped = page_record.fetch("ocr_skipped", [])
    reread = (removed - skipped).any? || (confirmed & skipped).any?

    replacement = upload_replacement_without(pages) if pages.any?
    swap_in(replacement, version) do
      changes = { page_record: page_record.merge("confirmed" => (page_record.fetch("confirmed", []) + confirmed).uniq) }
      if replacement
        self.content = without_page_texts(pages) if content.present?
        changes[:page_record]["map"] = page_map - removed
        changes.merge!(checksum: replacement[:checksum], page_count: page_count - pages.size)
      end
      update!(changes)
    end
    review_resolved!("blank_pages")

    if reread
      process_later(extract_metadata: false)
    elsif pages.any?
      reindex
    end
  end

  # Puts the upload back. The searchable PDF and thumbnail were made from
  # the edited pages, so they go too and processing makes new ones. The
  # stored original becomes the file again, so nothing is uploaded.
  def restore_original!(version: checksum)
    raise EditRefused, "This document is still processing." unless editable_pages?
    raise EditRefused, "There is no original to restore." unless original_file.attached?
    raise EditRefused, STALE_EDIT unless version == checksum

    blob = original_file.blob
    original_checksum, original_pages = blob.open { |copy| [ Digest::SHA256.file(copy.path).hexdigest, Pdf.page_count(copy.path) ] }

    swap_in(nil, version) do
      raise EditRefused, STALE_EDIT unless original_file.blob == blob

      self.file = blob
      self.original_file = nil
      self.archive_file = nil
      update!(checksum: original_checksum, page_record: {}, page_count: original_pages)
    end
    process_later(extract_metadata: false)
  end

  private
    # Every replacement file is made and stored before any is swapped in,
    # so neither a failure here nor one in storage later can leave the
    # document pointing at files that are not there.
    def upload_replacement_without(pages)
      blobs = {}
      with_file_copy do |path|
        Dir.mktmpdir do |dir|
          output = File.join(dir, "trimmed.pdf")
          Pdf.without_pages(path, pages, output)
          checksum = Digest::SHA256.file(output).hexdigest
          archive = trimmed_archive(pages, dir)
          image = Pdf.render_page(archive || output, 1, edge: 640, format: :jpeg) if pages.include?(1)

          # The upload is already stored, so its blob becomes the original
          # rather than a second copy of the same file.
          blobs[:original_file] = file.blob unless original_file.attached?
          blobs[:file] = upload_blob(File.open(output), file.filename, "application/pdf")
          blobs[:archive_file] = upload_blob(File.open(archive), archive_file.filename, "application/pdf") if archive
          blobs[:thumbnail] = upload_blob(StringIO.new(image), "thumbnail.jpg", "image/jpeg") if image
          { checksum: checksum, blobs: blobs }
        end
      end
    rescue StandardError
      discard_unattached(blobs)
      raise
    end

    # The blob row is saved only once its file is stored and there.
    def upload_blob(io, filename, content_type)
      blob = ActiveStorage::Blob.build_after_unfurling(io: io, filename: filename, content_type: content_type)
      begin
        blob.upload_without_unfurling(io)
        raise ActiveStorage::IntegrityError, "#{filename} was not stored" unless blob.service.exist?(blob.key)
        blob.tap(&:save!)
      rescue StandardError
        blob.delete
        raise
      end
    ensure
      io.close
    end

    # Swaps the stored replacement files in under the row lock, once the
    # document is still the version the edit was made against. The old
    # files go only after commit.
    def swap_in(replacement, version)
      blobs = replacement ? replacement[:blobs] : {}
      with_lock do
        raise EditRefused, STALE_EDIT unless editable_pages? && checksum == version

        blobs.each { |name, blob| public_send("#{name}=", blob) }
        yield
      end
    ensure
      discard_unattached(blobs)
    end

    def discard_unattached(blobs)
      blobs.each_value { |blob| blob.purge unless blob.attachments.exists? }
    end

    # Keyword search follows the new pages at once. Passages are embedded by
    # an index-only job, which reads and sends nothing again, so the edit
    # never waits on the search model loading or running in the web process.
    def reindex
      refresh_search_vector
      IndexDocumentJob.perform_later(self)
    end

    # The searchable PDF has the same pages as the file, so it loses the same
    # ones rather than waiting for OCR to run again. Returns its path.
    def trimmed_archive(pages, dir)
      return unless archive_file.attached?

      output = File.join(dir, "archive.pdf")
      archive_file.open { |archive| Pdf.without_pages(archive.path, pages, output) }
      output
    end

    # Text for the pages that stay, so page texts and chunk page numbers keep
    # matching the file.
    def without_page_texts(pages)
      texts = page_texts
      return content unless texts.size == page_count

      texts.reject.with_index(1) { |_text, page| pages.include?(page) }.join(Document::PAGE_BREAK)
    end
end
