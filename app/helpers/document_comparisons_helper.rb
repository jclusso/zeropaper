module DocumentComparisonsHelper
  def document_comparison(document, other)
    DocumentComparison.new(document, other)
  end

  # What two documents have in common, for the comparison page.
  class DocumentComparison
    Row = Struct.new(:label, :left, :right) do
      def same?
        left.to_s == right.to_s
      end
    end

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
        Row.new("Pages", left.page_count, right.page_count),
        Row.new("File size", view.number_to_human_size(left.file.blob&.byte_size), view.number_to_human_size(right.file.blob&.byte_size)),
        Row.new("Source", source(left), source(right)),
        Row.new("Added", left.created_at.to_fs(:long), right.created_at.to_fs(:long)),
        Row.new("Checksum", left.checksum.first(12), right.checksum.first(12))
      ]
    end

    # Similarity from 0 to 100: how much wording the two texts share, or
    # the cosine similarity of the local embeddings when either has no text.
    # Meaning alone rates forms from the same template as near identical.
    def similarity
      @similarity ||= ((shared_text || embedding_similarity || 0.0) * 100).round.clamp(0, 100)
    end

    def similarity_basis
      shared_text || !embedding_similarity ? "shared text" : "meaning"
    end

    def facts
      facts = []
      facts << (left.page_count == right.page_count ? "Same page count" : "Page count differs")
      facts << (left.file.blob&.byte_size == right.file.blob&.byte_size ? "Same file size" : "File size differs")
      facts << "Same date" if left.document_date && left.document_date == right.document_date
      facts << "Same correspondent" if left.correspondent && left.correspondent == right.correspondent
      facts
    end

    private
      def source(document)
        [ document.source.humanize, document.source_detail ].compact_blank.join(" · ")
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
        TextOverlap.new(left.content, right.content).text_score if left.content.present? && right.content.present?
      end
  end

  # Tells two documents with the same title apart in a confirmation.
  def comparison_identity(document)
    [ (pluralize(document.page_count, "page") if document.page_count), "added #{document.created_at.to_fs(:long)}" ].compact.join(", ")
  end
end
