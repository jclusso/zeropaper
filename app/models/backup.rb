# A backup of the whole library: files, OCR text, details, thumbnails and
# taxonomy, restorable into this or another instance.
#
# Backups are files in one folder, BACKUP_DIR, which Docker installs mount
# wherever they want them kept, such as a NAS share. Each is a zip encrypted
# with the backup key (see Backup::Envelope and Backup::Key), so a backup and
# that key are enough to restore after the server and its database are gone.
# A Backup record tracks one run; the folder is the list of backups.
class Backup < ApplicationRecord
  STATUSES = %w[pending processing ready failed].freeze
  FREQUENCIES = { "daily" => 1.day, "weekly" => 1.week }.freeze
  # How backups are grouped for keeping; weeks are ISO weeks.
  RETENTION = { "daily" => "%Y-%m-%d", "weekly" => "%G-%V", "monthly" => "%Y-%m", "yearly" => "%Y" }.freeze
  EXTENSION = ".zpbackup".freeze
  # Only files named like this are listed, restored, downloaded or pruned, so
  # nothing else in the folder is touched.
  FILENAME = /\Azeropaper-\d{4}-\d{2}-\d{2}-\d{6}\.zpbackup\z/
  ZIP_SIGNATURE = "PK\x03\x04".b.freeze

  Summary = Data.define(:made_at, :key_id, :own_key, :made_by, :documents_count, :private_documents_count)

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

      folder.children.select { |path| path.basename.to_s.match?(FILENAME) && !path.symlink? && path.file? }.sort.reverse
    end

    def file(name)
      files.find { |path| path.basename.to_s == name.to_s }
    end

    # A backup by its name without the extension, as it appears in URLs.
    def file_for(id)
      file("#{id}#{EXTENSION}")
    end

    def file_name(time = Time.current)
      "zeropaper-#{time.strftime("%Y-%m-%d-%H%M%S")}#{EXTENSION}"
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
    # changes. Nil when the file cannot be read.
    def summary(path)
      envelope = Backup::Envelope.new(path.to_s)
      key = Setting.instance.backup_key_bytes
      own_key = envelope.key_id == Backup::Key.id(key)
      metadata = own_key ? Rails.cache.fetch([ "backup-summary", path.to_s, path.mtime.to_i, path.size ]) { envelope.metadata(key) } : {}
      Summary.new(made_at: envelope.made_at, key_id: envelope.key_id, own_key: own_key, made_by: metadata["made_by"],
                  documents_count: metadata["documents_count"], private_documents_count: metadata["private_documents_count"])
    rescue Archive::Reader::InvalidArchive, SystemCallError
      nil
    end

    # Adds an uploaded backup to the folder, named for when it was made so it
    # sorts and prunes with the others. An encrypted backup is kept as it is;
    # a plain zip, such as an export from an older ZeroPaper, is checked and
    # encrypted with this ZeroPaper's key.
    def import(path)
      if Backup::Envelope.backup?(path)
        envelope = Backup::Envelope.new(path.to_s)
        name = new_file_name(envelope.made_at)
        key = Setting.instance.backup_key_bytes
        write_new(name, key: (key if envelope.key_id == Backup::Key.id(key))) do |file|
          File.open(path, "rb") { |upload| IO.copy_stream(upload, file) }
        end
      elsif File.binread(path, ZIP_SIGNATURE.bytesize) == ZIP_SIGNATURE
        reader = Archive::Reader.new(path.to_s)
        reader.verify!
        manifest = reader.manifest
        made_at = Time.zone.parse(manifest["exported_at"].to_s) || Time.current
        name = new_file_name(made_at)
        seal(path, name, made_at: made_at, metadata: manifest.slice("made_by", "documents_count", "private_documents_count"))
      else
        raise Archive::Reader::InvalidArchive, "That file is not a ZeroPaper backup."
      end
      folder.join(name)
    end

    # Decrypts a backup into a temporary zip for the block.
    def open_zip(path, key)
      Dir.mktmpdir do |dir|
        zip = File.join(dir, "backup.zip")
        File.open(zip, "wb") { |out| Backup::Envelope.new(path.to_s).decrypt(key, out) }
        yield zip
      end
    end

    # Keeps the newest backup of each of the last few days, weeks, months and
    # years that have one, as many of each as the schedule says, plus the
    # newest backup of all. The rest are removed.
    def prune
      setting = Setting.instance
      backups = files.index_with { |path| Time.zone.strptime(path.basename.to_s[/\d{4}-\d{2}-\d{2}-\d{6}/], "%Y-%m-%d-%H%M%S") }
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
      def new_file_name(made_at)
        file_name(made_at).tap do |name|
          raise Archive::Reader::InvalidArchive, "The backup from #{made_at.to_fs(:long)} is already in the folder." if folder.join(name).exist?
        end
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

  # Writes the zip to a local temporary folder, checks it, then encrypts it
  # into the backup folder. The plain zip never reaches the backup folder.
  def process!
    update!(status: "processing", error: nil)
    name = self.class.file_name(created_at)
    Dir.mktmpdir do |dir|
      zip = File.join(dir, "backup.zip")
      File.open(zip, "wb") { |file| Archive::Writer.new(Document.all, made_at: created_at, made_by: user&.name || "Schedule").write(file) }
      reader = Archive::Reader.new(zip)
      reader.verify!
      manifest = reader.manifest
      self.class.seal(zip, name, made_at: created_at, metadata: manifest.slice("made_by", "documents_count", "private_documents_count"))
      update!(status: "ready", filename: name, documents_count: manifest["documents_count"])
    end
  rescue ActiveRecord::Encryption::Errors::Decryption
    update!(status: "failed", error: "A document could not be decrypted. ZeroPaper is running with different encryption keys (SECRET_KEY_BASE) than the ones the library was saved with.")
  rescue StandardError => error
    update!(status: "failed", error: error.message.truncate(1_000))
  end
end
