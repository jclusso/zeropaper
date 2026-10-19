module DocumentComparisonsHelper
  def document_comparison(document, other)
    DocumentComparison.new(document, other)
  end

  # What two documents have in common, for the comparison page.
  class DocumentComparison
    # A detail of both documents. match overrides comparing the values, and
    # note says what the values alone do not.
    Row = Struct.new(:label, :left, :right, :match, :note) do
      def same?
        match.nil? ? left.to_s == right.to_s : match
      end
    end

    # One measure behind the similarity: its score, what it counted, how it
    # works, and whether it is the one that sets the score.
    Measure = Struct.new(:key, :label, :score, :detail, :explanation, :decides)

    PAGES_EXPLANATION = "Each page is shrunk to a small grid of light and dark and compared with the other document's pages, in order. " \
      "Blank pages and pages removed since upload are left out, and a removed page still matches when the other document has it. " \
      "Rescans of one sheet match. A small change, such as a different total, can still pass, so numbers are checked too.".freeze
    NUMBERS_EXPLANATION = "Words with a digit in them, at least three characters long: invoice and account numbers, dates, totals, VINs " \
      "and phone numbers. Two fills of one form share their wording but not these. Shown when both documents have at least three.".freeze
    WORDING_EXPLANATION = "Runs of three words found in both texts, out of all the runs in either. Two OCR reads of the same scan can take " \
      "columns in a different order, which breaks runs, and forms from one template share most of their words.".freeze
    CHECKSUM_NOTE = "A fingerprint of each file as uploaded, before any pages were removed or turned upright. " \
      "The same checksum means the same file.".freeze
    MEANING_EXPLANATION = "How close the two texts are in meaning, from the local embeddings. Used when a document has no text. " \
      "Forms from one template rate as near identical.".freeze

    attr_reader :left, :right

    def initialize(left, right)
      @left = left
      @right = right
    end

    def rows(view)
      [
        Row.new("Title", left.display_title, right.display_title),
        Row.new("Date", left.document_date&.to_fs(:long), right.document_date&.to_fs(:long)),
        Row.new("Correspondent", left.correspondent&.name, right.correspondent&.name),
        Row.new("Type", left.document_type&.name, right.document_type&.name),
        Row.new("Pages", page_summary(left), page_summary(right), same_pages?, pages_note),
        Row.new("File size", view.number_to_human_size(left.file.blob&.byte_size), view.number_to_human_size(right.file.blob&.byte_size)),
        Row.new("Checksum", upload_checksum(left), upload_checksum(right), nil, CHECKSUM_NOTE)
      ]
    end

    # Similarity from 0 to 100. For two PDFs, the share of pages that look
    # the same, held down by the share of numbers when both have enough:
    # the page check is coarse, and numbers tell two fills of one form
    # apart. Otherwise how much wording the two texts share, or the cosine
    # similarity of the local embeddings when either has no text. Wording is
    # a weak measure for scans: separate OCR runs read columns in different
    # orders, and forms from one template share most of their words.
    # Meaning alone rates such forms as near identical.
    def similarity
      @similarity ||= percent(page_score || shared_text || embedding_similarity || 0.0)
    end

    def similarity_explanation
      if page_score
        "For two PDFs the score is the share of matching pages#{", held down by the share of shared numbers" if numbers?}. " \
          "Wording is not counted: OCR can read one scan's columns in a different order each time, " \
          "and forms from one template share most of their words, so it scores copies and different fills alike."
      elsif shared_text || !embedding_similarity then WORDING_EXPLANATION
      else MEANING_EXPLANATION
      end
    end

    # :high when the checksums say they are one document or every measure
    # agrees fully, :medium while the score says they may be, else :low.
    def confidence
      if file_fact || similarity == 100 then :high
      elsif similarity >= 60 then :medium
      else :low
      end
    end

    # Only a checksum makes it certain, so a full score still reads as very
    # likely.
    def verdict
      case file_fact
      when "Same file" then "The same file"
      when "Same upload" then "The same upload"
      else
        if similarity >= 90 then "Very likely the same document"
        elsif similarity >= 60 then "Possibly the same document"
        else "Probably different documents"
        end
      end
    end

    # What to do next, for the confidence.
    def guidance
      case confidence
      when :high then "Keep the one with the details you want and delete the other."
      when :medium then "Look over the pages below before deleting either."
      else "Keep both unless the pages below show they are the same."
      end
    end

    # The measures the score is made from: pages and numbers for two PDFs,
    # otherwise wording or meaning. The one that sets the score comes first.
    def measures
      @measures ||= begin
        measures = []
        if page_score
          measures << Measure.new(:pages, "Matching pages", percent(matching_pages),
            "#{content_pairs.count { |pair| pair.all? }} of #{pluralize(content_pairs.size, "page")} with content", PAGES_EXPLANATION)
          if numbers?
            shared, total = text_overlap.number_counts
            measures << Measure.new(:numbers, "Shared numbers", percent(text_overlap.number_score), "#{shared} of #{pluralize(total, "number")} in both", NUMBERS_EXPLANATION)
          end
        elsif shared_text
          measures << Measure.new(:wording, "Shared wording", percent(shared_text), "Runs of three words in both", WORDING_EXPLANATION)
        elsif embedding_similarity
          measures << Measure.new(:meaning, "Meaning", percent(embedding_similarity), "From local embeddings", MEANING_EXPLANATION)
        end

        measures.min_by(&:score)&.decides = true
        measures.partition(&:decides).flatten
      end
    end

    # A page of one document in the comparison: page is its number now,
    # nil when it was removed; original is its number in the upload; blank
    # when it looks blank, removed or not.
    Sheet = Struct.new(:page, :original, :blank) do
      def removed?
        page.nil?
      end
    end

    # The two documents' pages side by side, as [left_sheet, right_sheet]
    # rows. PDFs are paired by how their pages look, counting pages removed
    # since upload, so a page only one has leaves a gap instead of shifting
    # every page after it; anything else pairs page for page.
    def page_pairs
      @page_pairs ||= matched_pages || (1..[ left.page_count.to_i, right.page_count.to_i ].max).map do |page|
        [ left, right ].map { Sheet.new(page, nil, it.blank_page?(page)) if page <= it.page_count.to_i }
      end
    end

    # Each document's sheet in every row, nil where it has none.
    def pages_of(document)
      page_pairs.map { |pair| pair[document == left ? 0 : 1] }
    end

    # Pages, in current numbering, that look blank and have no match in the
    # other document, such as blank backs the other had removed. The preview
    # leaves them out by default so the two viewers line up page for page.
    def unmatched_blank_pages(document)
      index = document == left ? 0 : 1
      page_pairs.filter_map do |pair|
        own, other = pair[index], pair[1 - index]
        own.page if own&.page && own.blank && (other.nil? || other.removed?)
      end
    end

    # Whether the preview leaves anything out by default: unmatched blank
    # pages, or pages removed since upload.
    def hidden_pages?
      [ left, right ].any? { unmatched_blank_pages(it).any? || from_upload?(it) }
    end

    # What a viewer shows, as [source, pages]: the file (:viewable) without
    # unmatched blank pages, or with show_blank every page of the upload
    # (:upload), removed ones included, so both line up page for page.
    def preview(document, show_blank:)
      if show_blank && from_upload?(document)
        [ :upload, pages_of(document).compact.map(&:original).sort ]
      else
        pages = (1..document.page_count.to_i).to_a
        [ :viewable, show_blank ? pages : pages - unmatched_blank_pages(document) ]
      end
    end

    # Each row's page in each viewer, keyed by document id, for linking the
    # two viewers. Numbers are positions in what each viewer shows.
    def viewer_pages(show_blank:)
      previews = [ left, right ].map { preview(it, show_blank: show_blank) }
      page_pairs.map do |pair|
        positions = pair.zip(previews).map do |sheet, (source, pages)|
          number = source == :upload ? sheet&.original : sheet&.page
          number && pages.index(number)&.+(1)
        end
        [ left.id, right.id ].zip(positions).to_h.compact
      end.reject(&:empty?)
    end

    private
      # Pages compared without blank ones, removed or not, since a copy with
      # its blank backs removed is otherwise the same.
      # Same pages when every page with content has a match, or, without
      # page images to pair, the same count of pages that are not blank.
      def same_pages?
        if matched_pages then content_pairs.any? && content_pairs.all? { |pair| pair.all? }
        else content_page_count(left) == content_page_count(right)
        end
      end

      # Pages with content only one document has; blank ones are left out.
      def pages_note
        return unless matched_pages

        only_left, only_right = content_pairs.count { |_, other| other.nil? }, content_pairs.count { |own, _| own.nil? }
        if content_pairs.none? { |pair| pair.all? } then "No pages match"
        elsif only_left.zero? && only_right.zero?
          left.page_count == right.page_count ? "Same pages" : "Same apart from blank pages"
        else
          [ ("#{pluralize(only_left, "page")} only in this document" if only_left.positive?),
            ("#{pluralize(only_right, "page")} only in the other" if only_right.positive?) ].compact.join(", ")
        end
      end

      # The upload's checksum: a file with pages removed or turned is unique
      # to its document, so only the upload can match another.
      def upload_checksum(document)
        document.upload_checksum.first(12)
      rescue StandardError
        document.checksum.first(12)
      end

      def content_page_count(document)
        document.page_count.to_i - document.suggested_blank_pages.size
      end

      # The page count, with pages removed since upload and blank pages
      # still there, which explain why two copies differ.
      def page_summary(document)
        removed = pages_of(document).count { it&.removed? } if matched_pages
        blank = document.suggested_blank_pages.size
        [ document.page_count, ("#{removed} removed" if removed.to_i.positive?), ("#{blank} #{blank == 1 ? "looks" : "look"} blank" if blank.positive?) ].compact.join(" · ")
      end

      def matched_pages
        return @matched_pages if defined?(@matched_pages)

        @matched_pages =
          if [ left, right ].all? { it.pdf? && it.page_count.to_i.positive? }
            sides = [ left, right ].map { sheets(it) }
            if sides.all?
              (left_sheets, left_hashes), (right_sheets, right_hashes) = sides
              # A blank page hashes close to one with little on it, so blank
              # pages pair only with blank pages.
              PageHash.pair(left_hashes, right_hashes) { |i, j| left_sheets[i].blank == right_sheets[j].blank }
                .map { |i, j| [ i && left_sheets[i - 1], j && right_sheets[j - 1] ] }
            end
          end
      rescue StandardError => error
        Rails.logger.warn("[comparison] pages could not be paired (#{error.class})")
        @matched_pages = nil
      end

      # A document's sheets and their hashes: every page of the upload when
      # pages were removed, so removed ones can be shown, or else its pages.
      def sheets(document)
        if document.original_file.attached? && document.page_map.size == document.page_count
          hashes = document.page_fingerprints(document.original_file)
          if hashes.size >= document.page_map.max.to_i
            blank = document.page_record.fetch("blank", []) - document.page_record.fetch("confirmed", [])
            sheets = hashes.each_index.map do |index|
              Sheet.new(document.current_page_number(index + 1), index + 1, blank.include?(index + 1))
            end
            return [ sheets, hashes ]
          end
        end

        hashes = document.page_fingerprints
        [ hashes.each_index.map { |index| Sheet.new(index + 1, nil, document.blank_page?(index + 1)) }, hashes ] if hashes.size == document.page_count
      end

      def pluralize(count, word)
        "#{count} #{word.pluralize(count)}"
      end

      def embedding_similarity
        return @embedding_similarity if defined?(@embedding_similarity)

        a, b = left.embedding, right.embedding
        @embedding_similarity =
          if a.present? && b.present?
            dot = a.zip(b).sum { |x, y| x * y }
            norm = Math.sqrt(a.sum { |x| x * x }) * Math.sqrt(b.sum { |y| y * y })
            norm.zero? ? nil : dot / norm
          end
      end

      def shared_text
        text_overlap&.text_score
      end

      def text_overlap
        @text_overlap ||= TextOverlap.new(left.content, right.content) if left.content.present? && right.content.present?
      end

      # Whether the document's pages were paired from its upload, which has
      # pages since removed.
      def from_upload?(document)
        pages_of(document).compact.any?(&:removed?)
      end

      def page_score
        [ matching_pages, (text_overlap.number_score if numbers?) ].compact.min if matching_pages
      end

      def numbers?
        text_overlap&.numbers?
      end

      # The only case where the two are certainly the same: one file, or one
      # upload before pages were removed or turned.
      def file_fact
        return @file_fact if defined?(@file_fact)

        @file_fact =
          if left.checksum == right.checksum then "Same file"
          elsif left.upload_checksum == right.upload_checksum then "Same upload"
          end
      rescue StandardError => error
        Rails.logger.warn("[comparison] uploads could not be compared (#{error.class})")
        @file_fact = nil
      end

      # Share of pages with content that look like a page of the other.
      def matching_pages
        content_pairs.count { |pair| pair.all? }.fdiv(content_pairs.size) if matched_pages && content_pairs.any?
      end

      # Page rows other than blank pages and pages removed from the upload.
      # Removed pages still count when the other has them, since they are
      # in the upload.
      def content_pairs
        @content_pairs ||= page_pairs.reject { |pair| pair.compact.all? { it.blank || it.removed? } }
      end

      def percent(score)
        (score * 100).round.clamp(0, 100)
      end
  end

  # When and how a document came in, which says nothing about whether two
  # are one document, so it sits on each card rather than in the table.
  def comparison_added(document)
    [ "Added #{document.created_at.to_fs(:long)}", document.source.humanize, document.source_detail ].compact_blank.join(" · ")
  end

  def comparison_heading(document, other)
    document.duplicate_of == other ? "Possible original" : "Other document"
  end

  # Tells two documents with the same title apart in a confirmation.
  def comparison_identity(document)
    [ (pluralize(document.page_count, "page") if document.page_count), "added #{document.created_at.to_fs(:long)}" ].compact.join(", ")
  end
end
