# Picks up files dropped into INGEST_DIR. Anything under its private/
# subfolder is private from the start, so it never reaches a hosted
# provider. Ingested files are removed; files ZeroPaper cannot read are moved
# to .unsupported/ so they are not retried forever.
#
# Symlinks, and anything under a symlinked folder, are skipped and left in
# place, so the folder cannot be used to import (or delete) files from the
# rest of the machine.
module Ingest
  class Folder
    PRIVATE_DIR = "private".freeze
    UNSUPPORTED_DIR = ".unsupported".freeze
    # Files changed more recently than this may still be being written.
    SETTLE_TIME = 10.seconds

    attr_reader :root

    def initialize(root = Setting.instance.ingest_path)
      @root = Pathname(root)
    end

    def scan
      prepare
      ready_files.each { |path| ingest(path) }
    end

    def prepare
      FileUtils.mkdir_p(root.join(PRIVATE_DIR))
    end

    private
      def ready_files
        Dir.glob("**/*", base: root).sort.filter_map do |relative|
          next if relative.split("/").any? { |segment| segment.start_with?(".") }

          path = root.join(relative)
          path if path.file? && path.mtime < SETTLE_TIME.ago
        end
      end

      def ingest(path)
        relative = path.relative_path_from(root).to_s
        private = relative.start_with?("#{PRIVATE_DIR}/")

        if symlinked?(relative)
          Rails.logger.warn("[ingest] #{relative}: skipped, symlinks are not imported")
          return
        end

        # NOFOLLOW also refuses a file swapped for a symlink after the check.
        File.open(path, File::RDONLY | File::NOFOLLOW | File::BINARY) do |io|
          Document.ingest!(
            io: io,
            filename: path.basename.to_s,
            source: "folder",
            source_detail: relative,
            private: private,
            private_reason: ("Added from the private folder" if private)
          )
        end
        path.delete
      rescue Document::Duplicate
        path.delete
      rescue Document::UnsupportedType, Document::TooLarge => error
        Rails.logger.warn("[ingest] #{relative}: #{error.class.name.demodulize}, moved to #{UNSUPPORTED_DIR}")
        target = root.join(UNSUPPORTED_DIR, relative)
        FileUtils.mkdir_p(target.dirname)
        FileUtils.mv(path, target)
      rescue StandardError => error
        # The message can quote what was read, so only the class is logged.
        Rails.logger.error("[ingest] #{relative}: #{error.class}")
      end

      # Whether the file, or any folder between it and the root, is a symlink.
      def symlinked?(relative)
        Pathname(relative).descend.any? { |part| root.join(part).symlink? }
      end
  end
end
