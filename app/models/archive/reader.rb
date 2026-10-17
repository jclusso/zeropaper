require "zip"

module Archive
  class Reader
    class InvalidArchive < StandardError; end
    class TooLarge < InvalidArchive; end

    CHUNK = 1.megabyte
    # Limits checked from the zip's directory before any entry is read.
    MAX_ENTRIES = 1_000_000
    MAX_MANIFEST_BYTES = 16.megabytes
    MAX_DETAILS_BYTES = 4.megabytes
    MAX_CONTENT_BYTES = 64.megabytes
    # The stored files of a document: its file, original, archive PDF and
    # thumbnail.
    STORED_FILE = %r{\Adocuments/\d+/(?:file/|original/|archive\.pdf\z|thumbnail\.jpg\z)}
    # Enough of a file for Marcel to tell its type.
    IDENTIFY_BYTES = 64.kilobytes
    # The types each kind of stored file may have.
    ATTACHMENT_TYPES = {
      file: Document::SUPPORTED_TYPES, original_file: Document::SUPPORTED_TYPES,
      archive_file: %w[application/pdf], thumbnail: %w[image/jpeg]
    }.freeze

    # One document's entries, as both a check and a restore read them.
    Record = Data.define(:folder, :details, :entries, :content_types) do
      def checksum = details["checksum"]
      def label = details["title"].presence || details["original_filename"].presence || folder
    end

    # +own_key+ is true for a backup sealed with this ZeroPaper's key, which
    # holds files this instance already stored, so they are bounded by the
    # whole backup limit rather than by MAX_UPLOAD_MB, which may have been
    # lowered since. Anything else may be anyone's and is held to the
    # stricter limit for each file.
    def initialize(path, restored_by: nil, own_key: false)
      @path = path
      @restored_by = restored_by
      @own_key = own_key
      @tempfiles = []
    end

    # Yields :restored or :skipped for each document in the archive.
    def each_result
      open do |zip|
        manifest = read_manifest(zip)
        restore_taxonomy(manifest)

        @checksums_seen = Hash.new(0)
        folders(zip).each do |folder|
          yield restore_document(zip, read_record(zip, folder))
        end
      end
    end

    def manifest
      open { |zip| read_manifest(zip) }
    end

    # Reads the whole archive so a damaged backup is refused before anything
    # is restored. Every document is read the way a restore reads it, every
    # entry is read in full and must match its CRC (rubyzip does not check),
    # and every document's file must match the checksum it was saved with.
    def verify!
      open do |zip|
        read_manifest(zip)
        checked = Set.new
        folders(zip).each do |folder|
          record = read_record(zip, folder)
          read_text(zip, "#{folder}content.txt", limit: MAX_CONTENT_BYTES)
          verify_checksum(record)
          checked.merge([ record.entries[:file]&.name, "#{folder}document.json", "#{folder}content.txt" ].compact)
        end
        zip.each { |entry| each_chunk(entry) { } if entry.file? && !checked.include?(entry.name) }
      end
    end

    private
      # Opens the zip once its directory is within the limits, so nothing is
      # read from an archive that would expand past them. rubyzip does not
      # hold entries to their declared sizes when streaming, so every read
      # goes through each_chunk, which does.
      def open
        raise TooLarge, "This backup has more than #{MAX_ENTRIES.to_fs(:delimited)} files." if Zip::File.count_entries(@path) > MAX_ENTRIES

        Zip::File.open(@path) do |zip|
          check_sizes(zip)
          yield zip
        end
      rescue Zip::Error, Zlib::Error, JSON::ParserError => error
        raise InvalidArchive, "This backup is damaged (#{error.message})."
      end

      def check_sizes(zip)
        total = zip.entries.sum do |entry|
          limit = entry_limit(entry.name)
          raise TooLarge, "#{entry.name} unzips to more than the #{limit / 1.megabyte} MB limit." if entry.size > limit

          entry.size
        end
        raise TooLarge, "This backup unzips to more than the #{UploadLimit.max_backup_bytes.to_fs(:human_size)} backup limit (MAX_BACKUP_GB)." if total > UploadLimit.max_backup_bytes
      end

      def entry_limit(name)
        case name
        when "manifest.json" then MAX_MANIFEST_BYTES
        when %r{\Adocuments/\d+/document\.json\z} then MAX_DETAILS_BYTES
        when %r{\Adocuments/\d+/content\.txt\z} then MAX_CONTENT_BYTES
        when STORED_FILE then @own_key ? UploadLimit.max_backup_bytes : UploadLimit.max_expanded_bytes
        else UploadLimit.max_expanded_bytes
        end
      end

      def read_manifest(zip)
        manifest = read_json(zip, "manifest.json", limit: MAX_MANIFEST_BYTES)
        raise InvalidArchive, "This is not a ZeroPaper backup." unless manifest.is_a?(Hash) && manifest["format"] == FORMAT
        raise InvalidArchive, "Backup version #{manifest["version"]} is newer than this ZeroPaper." if manifest["version"].to_i > VERSION

        %w[correspondents document_types tags rules].each do |list|
          raise InvalidArchive, "manifest.json is damaged." unless Array(manifest[list]).all?(Hash)
        end
        manifest
      end

      # A document's details and stored files, each file's type found from
      # its bytes rather than taken from the details, and refused unless
      # ZeroPaper keeps that kind of file.
      def read_record(zip, folder)
        details = read_json(zip, "#{folder}document.json", limit: MAX_DETAILS_BYTES)
        raise InvalidArchive, "#{folder}document.json is damaged." unless details.is_a?(Hash) && details["checksum"].is_a?(String)

        entries = {
          file: zip.glob("#{folder}file/*").first,
          original_file: zip.glob("#{folder}original/*").first,
          archive_file: zip.find_entry("#{folder}archive.pdf"),
          thumbnail: zip.find_entry("#{folder}thumbnail.jpg")
        }.compact
        record = Record.new(folder: folder, details: details, entries: entries, content_types: {})
        entries.each do |name, entry|
          type = identify(entry)
          raise InvalidArchive, "#{record.label} holds a #{type} file, which ZeroPaper does not keep." unless type.in?(ATTACHMENT_TYPES.fetch(name))

          record.content_types[name] = type
        end
        record
      end

      def verify_checksum(record)
        entry = record.entries[:file] or return
        digest = Digest::SHA256.new
        each_chunk(entry) { |chunk| digest << chunk }
        return if digest.hexdigest == record.checksum

        raise InvalidArchive, "#{record.label} does not match the checksum it was backed up with."
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

      # A document already in the library (same checksum) is skipped, but a
      # private copy in the backup makes it private, so the instruction is
      # not lost with the copy. Documents can share a file, so the second
      # with a checksum in the backup matches the second in the library.
      def restore_document(zip, record)
        details = record.details
        match = @checksums_seen[record.checksum]
        @checksums_seen[record.checksum] += 1
        if (existing = Document.where(checksum: record.checksum).order(:id).offset(match).first)
          return resume_restore(existing, details) if existing.source == "restore" && existing.status != "ready"

          existing.privatize!(reason: private_reason(details)) if details["private"]
          return :skipped
        end

        return :skipped unless record.entries[:file]

        document = Document.new(
          details.slice(*%w[title document_date summary private private_reason checksum original_filename
            page_count page_record source_detail text_source metadata_source ai_model confidence created_at])
        )
        document.content_type = record.content_types[:file]
        document.source = "restore"
        document.uploaded_by = @restored_by
        document.content = read_text(zip, "#{record.folder}content.txt", limit: MAX_CONTENT_BYTES)
        document.correspondent = Correspondent.named(details["correspondent"])
        document.document_type = DocumentType.named(details["document_type"])
        document.tags = Array(details["tags"]).filter_map { |name| Tag.named(name) }
        # Not ready until indexed, so a failed restore run resumes it.
        document.status = "processing"
        screen_for_privacy(document)

        record.entries.each { |name, entry| attach(document.public_send(name), entry, record.content_types[name]) }
        document.save!

        finish_restore(document)
      end

      # A document an earlier run stored but did not finish. The privacy it
      # has in the backup and this instance's rules, which may have changed
      # since, decide again before it is marked ready.
      def resume_restore(document, details)
        document.privatize_during_processing!(private_reason(details)) if details["private"]
        document.screen_before_content
        document.screen_for_privacy(document.content.to_s.tr(Document::PAGE_BREAK, "\n"))
        finish_restore(document)
      end

      def finish_restore(document)
        document.index!
        document.update!(status: "ready", error: nil)
        document.review_resolved!("failed")
        :restored
      ensure
        @tempfiles&.each(&:close!)
        @tempfiles = []
      end

      def private_reason(details)
        details["private_reason"].presence || "Private in a restored backup"
      end

      # This instance's mark-private rules decide too, on the filename, the
      # source and the restored text, before the files are stored and before
      # the document can be shared.
      def screen_for_privacy(document)
        return if document.private?

        if (rule = Rule.where(mark_private: true).matching(document, text: document.content.to_s.tr(Document::PAGE_BREAK, "\n")).first)
          document.assign_attributes(private: true, private_reason: rule.private_reason)
        end
      end

      # Copied through a temp file so large files are never held in memory.
      # It sits next to the zip, in the backup's scratch folder, and stays
      # open until the document is saved and uploads it.
      def attach(attachment, entry, content_type)
        file = Tempfile.new("restore", File.dirname(@path), binmode: true).tap { |tempfile| @tempfiles << tempfile }
        each_chunk(entry) { |chunk| file.write(chunk) }
        file.rewind
        attachment.attach(io: file, filename: File.basename(entry.name), content_type: content_type, identify: false)
      end

      def identify(entry)
        head = entry.get_input_stream { |stream| stream.read(IDENTIFY_BYTES) }.to_s
        Marcel::MimeType.for(StringIO.new(head), name: File.basename(entry.name))
      end

      def read_json(zip, name, limit:)
        JSON.parse(read_text(zip, name, limit: limit, required: true))
      end

      # An entry's text as a new UTF-8 string, empty when the entry is
      # missing or empty.
      def read_text(zip, name, limit:, required: false)
        entry = zip.find_entry(name)
        raise InvalidArchive, "#{name} is missing" if entry.nil? && required
        return String.new(encoding: Encoding::UTF_8) unless entry
        raise TooLarge, "#{name} is larger than #{limit / 1.megabyte} MB." if entry.size > limit

        text = String.new(capacity: [ entry.size, CHUNK ].min, encoding: Encoding::BINARY)
        each_chunk(entry) { |chunk| text << chunk }
        text.force_encoding(Encoding::UTF_8)
      end

      # Streams an entry, holding it to the size its directory declares and
      # to its CRC.
      def each_chunk(entry)
        size = 0
        crc = Zlib.crc32
        entry.get_input_stream do |stream|
          while (chunk = stream.read(CHUNK)) && !chunk.empty?
            size += chunk.bytesize
            raise InvalidArchive, "#{entry.name} is damaged." if size > entry.size

            crc = Zlib.crc32(chunk, crc)
            yield chunk
          end
        end
        raise InvalidArchive, "#{entry.name} is damaged." unless size == entry.size && crc == entry.crc
      end
  end
end
