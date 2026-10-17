# Picks up files dropped into INGEST_DIR. Anything under its private/
# subfolder is private from the start, so it never reaches a hosted
# provider. Ingested files are removed; files ZeroPaper cannot read are moved
# to .unsupported/ so they are not retried forever.
#
# Symlinks, and anything under a symlinked folder, are skipped and left in
# place, so the folder cannot be used to import (or delete) files from the
# rest of the machine. The opened file is checked against the path again, and
# again before it is deleted or moved, in case a folder on the way was swapped
# for a symlink in between.
#
# Filenames can say what a document is about, so logs name files by log_id.
module Ingest
  class Folder
    PRIVATE_DIR = "private".freeze
    UNSUPPORTED_DIR = ".unsupported".freeze
    # Files changed more recently than this may still be being written.
    SETTLE_TIME = 10.seconds

    class Moved < StandardError; end
    class Unsafe < StandardError; end

    # Files left in place because .unsupported could not be used, so each one
    # is logged once per process instead of on every scan.
    UNQUARANTINED = Concurrent::Set.new

    attr_reader :root

    # A short opaque name for a file in the logs, keyed with the app's secret
    # so it cannot be matched against guessed filenames.
    def self.log_id(relative)
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, relative.to_s).first(12)
    end

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
        id = self.class.log_id(relative)
        private = relative.start_with?("#{PRIVATE_DIR}/")
        stat = nil

        if symlinked?(relative)
          Rails.logger.warn("[ingest] #{id}: skipped, symlinks are not imported")
          return
        end

        begin
          # NOFOLLOW also refuses a file swapped for a symlink after the check.
          File.open(path, File::RDONLY | File::NOFOLLOW | File::BINARY) do |io|
            stat = io.stat
            ensure_unmoved(path, stat)
            Document.ingest!(
              io: io,
              filename: path.basename.to_s,
              source: "folder",
              source_detail: relative,
              private: private,
              private_reason: ("Added from the private folder" if private)
            )
          end
        rescue Document::Duplicate
        end
        ensure_unmoved(path, stat)
        path.delete
      rescue Moved
        Rails.logger.warn("[ingest] #{id}: skipped, its folder changed while it was read")
      rescue Document::UnsupportedType, Document::TooLarge => error
        quarantine(path, relative, stat, id, error)
      rescue Errno::ENOENT
        # Already gone. An SMB share keeps listing a deleted file for a while.
      rescue StandardError => error
        # The message can quote what was read, so only the class is logged.
        Rails.logger.error("[ingest] #{id}: #{error.class}")
      end

      # Moves a file that cannot be imported into .unsupported/, keeping its
      # place in the folder. The folders there are made one at a time and
      # none may be a symlink, so a planted link cannot send the file outside.
      def quarantine(path, relative, stat, id, error)
        ensure_unmoved(path, stat)
        target = root.join(UNSUPPORTED_DIR, relative)
        make_quarantine_dirs(Pathname(UNSUPPORTED_DIR).join(relative).dirname)
        File.rename(path, target)
        Rails.logger.warn("[ingest] #{id}: #{error.class.name.demodulize}, moved to #{UNSUPPORTED_DIR}")
      rescue Moved
        Rails.logger.warn("[ingest] #{id}: skipped, its folder changed while it was read")
      rescue Unsafe
        if UNQUARANTINED.add?(id)
          Rails.logger.warn("[ingest] #{id}: #{error.class.name.demodulize}, left in place because #{UNSUPPORTED_DIR} is or contains a symlink")
        end
      rescue SystemCallError => move_error
        Rails.logger.error("[ingest] #{id}: #{move_error.class}")
      end

      def make_quarantine_dirs(relative_dir)
        relative_dir.descend do |part|
          dir = root.join(part)
          begin
            Dir.mkdir(dir)
          rescue Errno::EEXIST
          end
          raise Unsafe unless File.lstat(dir).directory?
        end
        expected = root.realpath.join(relative_dir).to_s
        raise Unsafe unless File.realpath(root.join(relative_dir)) == expected
      end

      # Raises Moved unless the path still names the opened file, through
      # folders that stay inside the root.
      def ensure_unmoved(path, stat)
        current = File.lstat(path)
        same = current.file? && current.dev == stat.dev && current.ino == stat.ino
        raise Moved unless same && File.realpath(path).start_with?("#{root.realpath}/")
      rescue SystemCallError
        raise Moved
      end

      # Whether the file, or any folder between it and the root, is a symlink.
      def symlinked?(relative)
        Pathname(relative).descend.any? { |part| root.join(part).symlink? }
      end
  end
end
