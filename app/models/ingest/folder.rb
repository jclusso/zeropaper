# Picks up files dropped into INGEST_DIR. Anything under its private/
# subfolder is private from the start, so it never reaches a hosted
# provider. Ingested files are removed; files ZeroPaper cannot read are moved
# to .unsupported/ so they are not retried forever.
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

        File.open(path, "rb") do |io|
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
      rescue Document::UnsupportedType
        target = root.join(UNSUPPORTED_DIR, relative)
        FileUtils.mkdir_p(target.dirname)
        FileUtils.mv(path, target)
      rescue StandardError => error
        Rails.logger.error("[ingest] #{relative}: #{error.class}: #{error.message}")
      end
  end
end
