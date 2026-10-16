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

    def manifest
      Zip::File.open(@path) { |zip| read_manifest(zip) }
    rescue Zip::Error, JSON::ParserError => error
      raise InvalidArchive, "This backup is damaged (#{error.message})."
    end

    # Reads the whole archive so a damaged backup is refused before anything
    # is restored: every entry must match its CRC (rubyzip does not check),
    # and every document's file must match the checksum it was saved with.
    def verify!
      Zip::File.open(@path) do |zip|
        read_manifest(zip)
        zip.each do |entry|
          next unless entry.file?
          raise InvalidArchive, "#{entry.name} is damaged." unless Zlib.crc32(entry.get_input_stream.read) == entry.crc
        end
        folders(zip).each { |folder| verify_document(zip, folder) }
      end
    rescue Zip::Error, Zlib::Error, JSON::ParserError => error
      raise InvalidArchive, "This backup is damaged (#{error.message})."
    end

    private
      def verify_document(zip, folder)
        details = JSON.parse(read(zip, "#{folder}document.json"))
        entry = zip.glob("#{folder}file/*").first or return
        return if Digest::SHA256.hexdigest(entry.get_input_stream.read) == details["checksum"]

        raise InvalidArchive, "#{details["title"].presence || details["original_filename"]} does not match the checksum it was backed up with."
      end

      def read_manifest(zip)
        entry = zip.find_entry("manifest.json") or raise InvalidArchive, "manifest.json is missing"
        manifest = JSON.parse(entry.get_input_stream.read)
        raise InvalidArchive, "This is not a ZeroPaper backup." unless manifest["format"] == FORMAT
        raise InvalidArchive, "Backup version #{manifest["version"]} is newer than this ZeroPaper." if manifest["version"].to_i > VERSION

        manifest
      end

      def restore_taxonomy(manifest)
        Array(manifest["correspondents"]).each do |attributes|
          correspondent = upsert_named(Correspondent, attributes)
          # Older exports marked a correspondent's documents private; that is a rule now.
          Rule.privatize_mentions_of!(correspondent) if attributes["private_documents"]
        end
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
        screen_for_privacy(document)

        attach(document.file, file_entry)
        attach(document.original_file, zip.glob("#{folder}original/*").first)
        attach(document.archive_file, zip.find_entry("#{folder}archive.pdf"))
        attach(document.thumbnail, zip.find_entry("#{folder}thumbnail.jpg"))
        document.save!

        document.index!
        :restored
      end

      # This instance's mark-private rules decide too, on the filename, the
      # source and the restored text, before the files are stored and before
      # the document can be shared. Runs before attaching so private files go
      # straight to the encrypted service.
      def screen_for_privacy(document)
        return if document.private?

        if (rule = Rule.where(mark_private: true).matching(document, text: document.content.to_s.tr(Document::PAGE_BREAK, "\n")).first)
          document.assign_attributes(private: true, private_reason: rule.private_reason)
        end
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
