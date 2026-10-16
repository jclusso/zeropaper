require "zip"

module Archive
  class Reader
    class InvalidArchive < StandardError; end

    def initialize(path, restored_by: nil)
      @path = path
      @restored_by = restored_by
    end

    # Yields :restored or :skipped for each document in the archive.
    def each_result
      Zip::File.open(@path) do |zip|
        manifest = read_manifest(zip)
        restore_taxonomy(manifest)

        folders(zip).each do |folder|
          yield restore_document(zip, folder)
        end
      end
    end

    private
      def read_manifest(zip)
        entry = zip.find_entry("manifest.json") or raise InvalidArchive, "manifest.json is missing"
        manifest = JSON.parse(entry.get_input_stream.read)
        raise InvalidArchive, "This is not a ZeroPaper export." unless manifest["format"] == FORMAT
        raise InvalidArchive, "Export version #{manifest["version"]} is newer than this ZeroPaper." if manifest["version"].to_i > VERSION

        manifest
      end

      def restore_taxonomy(manifest)
        Array(manifest["correspondents"]).each { |attributes| upsert_named(Correspondent, attributes) }
        Array(manifest["document_types"]).each { |attributes| upsert_named(DocumentType, attributes) }
        Array(manifest["tags"]).each { |attributes| upsert_named(Tag, attributes) }
        Array(manifest["rules"]).each do |attributes|
          next if Rule.exists?(name: attributes["name"])

          Rule.create!(
            attributes.slice("name", "enabled", "position", "match_mode", "conditions", "mark_private").merge(
              correspondent: Correspondent.named(attributes["correspondent"]),
              document_type: DocumentType.named(attributes["document_type"]),
              tag_ids: Array(attributes["tags"]).filter_map { |name| Tag.named(name)&.id }
            )
          )
        end
      end

      def upsert_named(model, attributes)
        model.named(attributes["name"]) || model.create!(attributes.slice(*model.attribute_names))
      end

      def folders(zip)
        zip.entries.filter_map { |entry| entry.name[%r{\Adocuments/\d+/}] }.uniq
      end

      def restore_document(zip, folder)
        details = JSON.parse(read(zip, "#{folder}document.json"))
        return :skipped if Document.exists?(checksum: details["checksum"])

        file_entry = zip.glob("#{folder}file/*").first or return :skipped
        document = Document.new(
          details.slice(*%w[title document_date summary private private_reason checksum original_filename
            content_type page_count page_record source_detail text_source metadata_source ai_model confidence created_at])
        )
        document.source = "restore"
        document.uploaded_by = @restored_by
        document.content = read(zip, "#{folder}content.txt")
        document.correspondent = Correspondent.named(details["correspondent"])
        document.document_type = DocumentType.named(details["document_type"])
        document.tags = Array(details["tags"]).filter_map { |name| Tag.named(name) }
        document.status = "ready"

        attach(document.file, file_entry)
        attach(document.original_file, zip.glob("#{folder}original/*").first)
        attach(document.archive_file, zip.find_entry("#{folder}archive.pdf"))
        attach(document.thumbnail, zip.find_entry("#{folder}thumbnail.jpg"))
        document.save!

        document.index!
        :restored
      end

      def attach(attachment, entry)
        return unless entry

        attachment.attach(io: StringIO.new(entry.get_input_stream.read), filename: File.basename(entry.name))
      end

      def read(zip, name)
        zip.find_entry(name)&.get_input_stream&.read.to_s.force_encoding(Encoding::UTF_8)
      end
  end
end
