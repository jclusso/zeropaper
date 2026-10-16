# A backup of the whole library: files, OCR text, details, thumbnails and
# taxonomy, restorable into this or another instance.
#
# Backups are files in one folder, BACKUP_DIR, which Docker installs mount
# wherever they want them kept, such as a NAS share. Each is a zip encrypted
# with the backup key (see Backup::Envelope and Backup::Key), so a backup and
# that key are enough to restore after the server and its database are gone.
# A Backup record tracks one run; the folder is the list of backups.
class Backup < ApplicationRecord
  include RunsAlone

  STATUSES = %w[pending processing ready failed].freeze
  FREQUENCIES = { "daily" => 1.day, "weekly" => 1.week }.freeze
  # How backups are grouped for keeping; weeks are ISO weeks.
  RETENTION = { "daily" => "%Y-%m-%d", "weekly" => "%G-%V", "monthly" => "%Y-%m", "yearly" => "%Y" }.freeze
  EXTENSION = ".zpbackup".freeze
  # Only files named like this are listed, restored, downloaded or pruned, so
  # nothing else in the folder is touched. Uploaded backups end in
  # "-uploaded" and are never pruned: they were added on purpose, and the
  # date in their name is only what the file says.
  FILENAME = /\Azeropaper-\d{4}-\d{2}-\d{2}-\d{6}(-uploaded)?\.zpbackup\z/
  MADE_HERE = /\Azeropaper-(\d{4}-\d{2}-\d{2}-\d{6})\.zpbackup\z/
  ZIP_SIGNATURE = "PK\x03\x04".b.freeze

  # What the folder listing shows for a backup. Without a key id the file
  # could not be read.
  Summary = Data.define(:made_at, :size, :key_id, :own_key, :made_by, :documents_count, :private_documents_count) do
    def readable? = key_id.present?
  end

  belongs_to :user, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  class << self
    def folder
      Pathname(Rails.configuration.x.backup_dir)
    end

    # Backups in the folder, newest first. Symlinks are left out, so a link
    # planted in a shared folder cannot point a download, restore or prune at
    # some other file.
    def files
      return [] unless folder.directory?

      folder.children.select { |path| path.basename.to_s.match?(FILENAME) && !path.symlink? && path.file? && openable?(path) }.sort.reverse
    end

    def file(name)
      files.find { |path| path.basename.to_s == name.to_s }
    end

    # A backup by its name without the extension, as it appears in URLs.
    def file_for(id)
      file("#{id}#{EXTENSION}")
    end

    def file_name(time = Time.current, uploaded: false)
      "zeropaper-#{time.strftime("%Y-%m-%d-%H%M%S")}#{"-uploaded" if uploaded}#{EXTENSION}"
    end

    # Opens a backup for reading only while it is still the regular file it
    # was when checked, so a file swapped for a link after the folder was
    # listed is not followed, and one swapped for a FIFO does not hang the
    # open. Without a block the caller closes the file.
    def open_file(path)
      stat = File.lstat(path)
      raise Backup::Envelope::Invalid, "#{File.basename(path)} is not a regular file." unless stat.file?

      io = File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK | File::BINARY)
      unless io.stat.dev == stat.dev && io.stat.ino == stat.ino
        io.close
        raise Backup::Envelope::Invalid, "#{File.basename(path)} changed while it was opened."
      end
      return io unless block_given?

      begin
        yield io
      ensure
        io.close
      end
    rescue Errno::ELOOP
      raise Backup::Envelope::Invalid, "#{File.basename(path)} is a link, not a backup."
    end

    # Backups still running, and failures since the last one that worked.
    def unfinished
      last_ready = where(status: "ready").maximum(:created_at)
      runs = recent.where.not(status: "ready")
      last_ready ? runs.where(created_at: last_ready..) : runs.limit(5)
    end

    # Called every hour. Starts a backup when the last one that did not fail
    # is older than the chosen interval. The half hour of slack keeps it from
    # drifting an hour later each time.
    def run_scheduled
      setting = Setting.instance
      return unless setting.backup_enabled?

      last = where.not(status: "failed").maximum(:created_at)
      return if last && last > (setting.backup_interval - 30.minutes).ago

      create!.tap do |backup|
        backup.process!
        prune if backup.status == "ready"
      end
    end

    # What a backup says about itself. Its date and key show without the key;
    # the rest needs this ZeroPaper's key and is cached until the file
    # changes. A file that cannot be read, whatever is wrong with it, is
    # listed as unreadable rather than taking the page down.
    def summary(path)
      stat = File.lstat(path)
      envelope = Backup::Envelope.new(path.to_s)
      key = Setting.instance.backup_key_bytes
      own_key = envelope.key_id == Backup::Key.id(key)
      metadata = own_key ? Rails.cache.fetch([ "backup-summary", path.to_s, stat.mtime.to_i, stat.size ]) { envelope.metadata(key) } : {}
      metadata = {} unless metadata.is_a?(Hash)
      Summary.new(made_at: envelope.made_at, size: stat.size, key_id: envelope.key_id, own_key: own_key, made_by: metadata["made_by"],
                  documents_count: metadata["documents_count"], private_documents_count: metadata["private_documents_count"])
    rescue StandardError => error
      Rails.logger.warn("Backup #{File.basename(path)} cannot be read: #{error.class}")
      Summary.new(made_at: stat&.mtime, size: stat&.size, key_id: nil, own_key: false, made_by: nil, documents_count: nil, private_documents_count: nil)
    end

    # Adds an uploaded backup to the folder, named for when it was made so it
    # sorts with the others, and marked as uploaded so it is never pruned.
    # An encrypted backup is kept as it is, after every chunk is checked when
    # it was made with this ZeroPaper's key; the restore checks the rest. A
    # plain zip, such as an export from an older ZeroPaper, is checked and
    # encrypted with this ZeroPaper's key. A date in the future, which
    # nothing vouches for, becomes now.
    def import(path)
      if File.size(path) > UploadLimit.max_backup_bytes
        raise Archive::Reader::TooLarge, "That file is larger than the #{UploadLimit.max_backup_bytes.to_fs(:human_size)} backup limit (MAX_BACKUP_GB)."
      end

      if Backup::Envelope.backup?(path)
        envelope = Backup::Envelope.new(path.to_s)
        name = new_file_name([ envelope.made_at, Time.current ].min)
        key = Setting.instance.backup_key_bytes
        own_key = envelope.key_id == Backup::Key.id(key)
        write_new(name, key: (key if own_key)) do |file|
          File.open(path, "rb") { |upload| IO.copy_stream(upload, file) }
        end
      elsif File.binread(path, ZIP_SIGNATURE.bytesize) == ZIP_SIGNATURE
        reader = Archive::Reader.new(path.to_s)
        reader.verify!
        manifest = reader.manifest
        made_at = export_time(manifest["exported_at"])
        name = new_file_name(made_at)
        seal(path, name, made_at: made_at, metadata: manifest.slice("made_by", "documents_count", "private_documents_count"))
      else
        raise Archive::Reader::InvalidArchive, "That file is not a ZeroPaper backup."
      end
      folder.join(name)
    end

    # Decrypts a backup into a zip in a scratch folder for the block. The
    # folder goes when the block ends, or at the next boot or run if the
    # process dies first.
    def open_zip(path, key)
      Backup::Scratch.open do |dir|
        zip = dir.join("backup.zip").to_s
        File.open(zip, File::WRONLY | File::CREAT | File::EXCL, 0o600, binmode: true) { |out| Backup::Envelope.new(path.to_s).decrypt(key, out) }
        yield zip
      end
    end

    # Keeps the newest backup of each of the last few days, weeks, months and
    # years that have one, as many of each as the schedule says, plus the
    # newest backup of all. The rest are removed. Only backups made here with
    # this key are pruned or take a place: uploaded ones, ones made with
    # another key and ones dated in the future are left alone.
    def prune
      setting = Setting.instance
      key_id = Backup::Key.id(setting.backup_key_bytes)
      backups = files.filter_map do |path|
        stamp = path.basename.to_s[MADE_HERE, 1] or next
        made_at = Time.zone.strptime(stamp, "%Y-%m-%d-%H%M%S")
        [ path, made_at ] if made_at <= Time.current && own_key?(path, key_id)
      end.to_h
      return if backups.empty?

      kept = Set[backups.keys.first]
      RETENTION.each do |period, format|
        newest_per_period = backups.uniq { |_path, made_at| made_at.strftime(format) }
        kept.merge(newest_per_period.first(setting.public_send("backup_keep_#{period}")).map(&:first))
      end
      backups.each_key { |path| path.delete unless kept.include?(path) }
    end

    def seal(zip, name, made_at:, metadata:)
      key = Setting.instance.backup_key_bytes
      write_new(name, key: key) { |file| Backup::Envelope.seal(zip, file, key: key, made_at: made_at, metadata: metadata) }
    end

    private
      # A backup deleted from an SMB share stays listed for a while after,
      # but can no longer be opened. It is opened without blocking, so a
      # FIFO cannot hang the listing.
      def openable?(path)
        File.open(path, File::RDONLY | File::NONBLOCK) { true }
      rescue Errno::ENOENT
        false
      end

      def new_file_name(made_at)
        if [ file_name(made_at), file_name(made_at, uploaded: true) ].any? { |name| folder.join(name).exist? }
          raise Archive::Reader::InvalidArchive, "The backup from #{made_at.to_fs(:long)} is already in the folder."
        end

        file_name(made_at, uploaded: true)
      end

      # An older export's date, which nothing vouches for either: one that
      # cannot be read or is in the future becomes now.
      def export_time(value)
        time = Time.iso8601(value.to_s).in_time_zone
        time <= Time.current ? time : Time.current
      rescue ArgumentError
        Time.current
      end

      def own_key?(path, key_id)
        Backup::Envelope.new(path.to_s).key_id == key_id
      rescue Archive::Reader::InvalidArchive, SystemCallError
        false
      end

      # Writes under a hidden name, reads it back to check every chunk when
      # the key is at hand, and renames it when it is sound, so a half written
      # or damaged backup is never listed. The file must be new and must not
      # be a symlink, so a link left in a shared folder cannot make ZeroPaper
      # write somewhere else; renaming over a link replaces the link.
      def write_new(name, key:)
        FileUtils.mkdir_p(folder)
        raise "The backup folder #{folder} is not writable by ZeroPaper." unless folder.writable?

        partial = folder.join(".#{name}.partial")
        created = false
        File.open(partial, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600, binmode: true) do |file|
          created = true
          yield file
        end
        key ? Backup::Envelope.new(partial.to_s).decrypt(key) : Backup::Envelope.new(partial.to_s).header
        File.rename(partial, folder.join(name))
      ensure
        partial.delete if created && partial.exist?
      end
  end

  def process_later
    BackupJob.perform_later(self)
  end

  # Writes the zip to a scratch folder, checks it the way a restore reads
  # it, then encrypts it into the backup folder. The plain zip never reaches
  # the backup folder. A backup runs once, however often its job does.
  def process!
    run_alone do
      update!(status: "processing", error: nil)
      name = self.class.file_name(created_at)
      Backup::Scratch.open do |dir|
        zip = dir.join("backup.zip").to_s
        File.open(zip, File::WRONLY | File::CREAT | File::EXCL, 0o600, binmode: true) do |file|
          Archive::Writer.new(Document.all, made_at: created_at, made_by: user&.name || "Schedule").write(file)
        end
        reader = Archive::Reader.new(zip, own_key: true)
        reader.verify!
        manifest = reader.manifest
        self.class.seal(zip, name, made_at: created_at, metadata: manifest.slice("made_by", "documents_count", "private_documents_count"))
        update!(status: "ready", filename: name, documents_count: manifest["documents_count"])
      end
    end
  rescue ActiveRecord::Encryption::Errors::Decryption
    update!(status: "failed", error: "A document could not be decrypted. ZeroPaper is running with different encryption keys (SECRET_KEY_BASE) than the ones the library was saved with.")
  rescue StandardError => error
    update!(status: "failed", error: error.message.truncate(1_000))
  end
end
