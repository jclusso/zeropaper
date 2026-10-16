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

  def editable_pages?
    pdf? && file.attached? && !status.in?(%w[pending processing])
  end

  # Removes pages (current numbering). The upload is kept in original_file
  # so it can be restored. OCR runs again only when the text no longer
  # matches the pages: removing pages OCR skipped drops their (empty) text
  # and reindexes locally, while removing a page that was read or keeping
  # one that was skipped reads the document again.
  def remove_pages!(pages, keep_blank: [])
    raise EditRefused, "This document is still processing." unless editable_pages?

    pages = pages.map(&:to_i).uniq.sort & (1..page_count).to_a
    raise EditRefused, "A document needs at least one page." if pages.size >= page_count

    removed = pages.map { |page| original_page_number(page) }
    confirmed = keep_blank.map { |page| original_page_number(page.to_i) }.compact
    skipped = page_record.fetch("ocr_skipped", [])
    reread = (removed - skipped).any? || (confirmed & skipped).any?

    if pages.any?
      replace_file_without(pages, removed)
    end
    update!(page_record: page_record.merge("confirmed" => (page_record.fetch("confirmed", []) + confirmed).uniq))
    review_resolved!("blank_pages")

    if reread
      process_later(extract_metadata: false)
    elsif pages.any?
      index!
    end
  end

  # Puts the upload back. The searchable PDF and thumbnail were made from
  # the edited pages, so they go too and processing makes new ones.
  def restore_original!
    raise EditRefused, "This document is still processing." unless editable_pages?
    raise EditRefused, "There is no original to restore." unless original_file.attached?

    blob = original_file.blob
    data = blob.download
    checksum = Digest::SHA256.hexdigest(data)
    ensure_checksum_free!(checksum)

    self.file = { io: StringIO.new(data), filename: blob.filename, content_type: blob.content_type }
    update!(checksum: checksum, page_record: {}, page_count: nil)
    original_file.purge
    archive_file.purge
    process_later(extract_metadata: false)
  end

  private
    # Every replacement file is made before any is swapped in, and the swap
    # is one save, so a failure partway leaves the document as it was.
    def replace_file_without(pages, removed)
      with_file_copy do |path|
        Dir.mktmpdir do |dir|
          output = File.join(dir, "trimmed.pdf")
          Pdf.without_pages(path, pages, output)
          data = File.binread(output)
          checksum = Digest::SHA256.hexdigest(data)
          ensure_checksum_free!(checksum)
          archive = trimmed_archive(pages, dir)
          image = Pdf.render_page(output, 1, edge: 640, format: :jpeg) if pages.include?(1)

          self.original_file = { io: File.open(path), filename: file.filename, content_type: file.content_type } unless original_file.attached?
          self.file = { io: StringIO.new(data), filename: file.filename, content_type: "application/pdf" }
          self.archive_file = { io: File.open(archive), filename: archive_file.filename, content_type: "application/pdf" } if archive
          self.thumbnail = { io: StringIO.new(image), filename: "thumbnail.jpg", content_type: "image/jpeg" } if image
          self.content = without_page_texts(pages) if content.present?
          update!(
            checksum: checksum,
            page_count: page_count - pages.size,
            page_record: page_record.merge("map" => page_map - removed)
          )
        end
      end
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

    def ensure_checksum_free!(checksum)
      return unless Document.where.not(id: id).exists?(checksum: checksum)

      raise EditRefused, "Another document already has exactly these pages."
    end
end
