module Document::Ingestible
  extend ActiveSupport::Concern

  SUPPORTED_TYPES = %w[
    application/pdf
    image/png image/jpeg image/tiff image/webp image/heic
    text/plain text/markdown text/csv
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
  ].freeze

  class UnsupportedType < StandardError; end
  class Duplicate < StandardError
    attr_reader :document

    def initialize(document)
      @document = document
      super("Already in the library as “#{document.display_title}”")
    end
  end

  class_methods do
    # Adds a file to the library and queues processing. Raises Duplicate when
    # the same bytes are already stored and UnsupportedType for formats the
    # pipeline cannot read. A private copy of a stored document makes that
    # document private, so the instruction is not lost with the duplicate.
    def ingest!(io:, filename:, source:, private: false, private_reason: nil, uploaded_by: nil, source_detail: nil)
      data = io.read
      content_type = Marcel::MimeType.for(StringIO.new(data), name: filename)
      raise UnsupportedType, "#{filename} is not a supported file type" unless content_type.in?(SUPPORTED_TYPES)

      checksum = Digest::SHA256.hexdigest(data)
      if (existing = find_by(checksum: checksum))
        existing.privatize!(reason: private_reason.presence || "Added again as private") if private
        raise Duplicate, existing
      end

      document = new(
        original_filename: filename,
        content_type: content_type,
        checksum: checksum,
        source: source,
        source_detail: source_detail,
        uploaded_by: uploaded_by,
        private: private,
        private_reason: private_reason
      )
      if !private && (rule = Rule.matching_before_content(document).find(&:mark_private?))
        document.assign_attributes(private: true, private_reason: rule.private_reason)
      end
      document.file.attach(io: StringIO.new(data), filename: filename, content_type: content_type)
      document.save!
      document.process_later
      document
    end
  end
end
