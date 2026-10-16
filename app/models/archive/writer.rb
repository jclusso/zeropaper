require "zip"

# Writes documents and taxonomy into a zip:
#
#   manifest.json                     format version and taxonomy
#   documents/<id>/document.json      details
#   documents/<id>/content.txt        text, pages separated by form feeds
#   documents/<id>/file/<name>        the current file
#   documents/<id>/original/<name>    the upload before pages were removed
#   documents/<id>/archive.pdf        searchable PDF made by OCR
#   documents/<id>/thumbnail.jpg
module Archive
  class Writer
    def initialize(documents)
      @documents = documents
    end

    def write(path)
      Zip::OutputStream.open(path) do |zip|
        add(zip, "manifest.json", JSON.pretty_generate(manifest))
        @documents.includes(:correspondent, :document_type, :tags).find_each { |document| add_document(zip, document) }
      end
    end

    private
      def manifest
        {
          format: FORMAT,
          version: VERSION,
          exported_at: Time.current.iso8601,
          correspondents: Correspondent.alphabetically.map { |record| record.slice(:name, :auto_match, :private_documents) },
          document_types: DocumentType.alphabetically.map { |record| record.slice(:name, :auto_match) },
          tags: Tag.alphabetically.map { |record| record.slice(:name, :color, :auto_match) },
          rules: Rule.ordered.map do |rule|
            rule.slice(:name, :enabled, :position, :match_mode, :conditions, :mark_private).merge(
              correspondent: rule.correspondent&.name,
              document_type: rule.document_type&.name,
              tags: rule.tags.map(&:name)
            )
          end
        }
      end

      def add_document(zip, document)
        folder = "documents/#{document.id}"
        add(zip, "#{folder}/document.json", JSON.pretty_generate(details(document)))
        add(zip, "#{folder}/content.txt", document.content.to_s)
        add_attachment(zip, document.file, "#{folder}/file/#{document.file.filename}")
        add_attachment(zip, document.original_file, "#{folder}/original/#{document.original_file.filename}") if document.original_file.attached?
        add_attachment(zip, document.archive_file, "#{folder}/archive.pdf")
        add_attachment(zip, document.thumbnail, "#{folder}/thumbnail.jpg")
      end

      def details(document)
        document.slice(
          :title, :document_date, :summary, :private, :private_reason, :checksum,
          :original_filename, :content_type, :page_count, :page_record, :source, :source_detail,
          :text_source, :metadata_source, :ai_model, :confidence, :created_at
        ).merge(
          correspondent: document.correspondent&.name,
          document_type: document.document_type&.name,
          tags: document.tags.map(&:name)
        )
      end

      def add_attachment(zip, attachment, name)
        return unless attachment.attached?

        add(zip, name, attachment.download)
      end

      def add(zip, name, data)
        zip.put_next_entry(name)
        zip.write(data)
      end
  end
end
