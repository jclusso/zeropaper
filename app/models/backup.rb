# A backup of the whole library: files, OCR text, details, thumbnails and
# taxonomy, restorable into this or another instance.
#
# Backups are files in one folder, BACKUP_DIR, which Docker installs mount
# wherever they want them kept, such as a NAS share. Each is a zip encrypted
# with the backup key (see Backup::Envelope and Backup::Key), so a backup and
# that key are enough to restore after the server and its database are gone.
#
# A Backup record tracks a run and then the file it made, or an uploaded
# file. The records are the list of backups: only ZeroPaper adds or removes
# them, and the folder is never read to decide what exists. A file gone from
# a folder that can be reached marks its backup missing instead of removing
# it, and nothing is pruned or deleted while the folder cannot be reached,
# such as when the share it is on is not mounted.
class Backup < ApplicationRecord
  include RunsAlone

  class Unreachable < StandardError; end

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
  # Open Backups pages refresh on this stream whenever a backup or restore
  # changes.
  STREAM = :backups

  belongs_to :user, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :stored, -> { where(status: "ready") }

  after_commit -> { self.class.broadcast_changes }

  class << self
    def broadcast_changes
      Turbo::StreamsChannel.broadcast_refresh_later_to STREAM
    end

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

    def reachable?
      folder.directory? && folder.readable?
    end

    def unreachable_message
      "The backup folder #{folder} cannot be reached. Check that the share it is on is mounted."
    end

    # Adds records for backup files in the folder that have none, such as
    # ones from before backups were recorded. Run by hand with
    # bin/rails backups:record_existing_files; it never removes a record.
    # Returns how many were added.
    def record_existing_files
      raise Unreachable, unreachable_message unless reachable?

      known = stored.pluck(:filename).to_set
      files.reject { |path| known.include?(path.basename.to_s) }.count do |path|
        create!(status: "ready", filename: path.basename.to_s, **details(path))
      end
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
    # Backups are dated by when they were made, since a file recorded from
    # the folder gets its record long after.
    def unfinished
      last_ready = stored.where(uploaded: false).maximum(:made_at)
      runs = recent.where.not(status: "ready")
      last_ready ? runs.where(created_at: last_ready..) : runs.limit(5)
    end

    # Called every hour. Starts a backup when the last one that did not fail
    # is older than the chosen interval. The half hour of slack keeps it from
    # drifting an hour later each time.
    def run_scheduled
      setting = Setting.instance
      return unless setting.backup_enabled?

      last = where(uploaded: false).where.not(status: "failed").maximum(Arel.sql("COALESCE(made_at, created_at)"))
      return if last && last > (setting.backup_interval - 30.minutes).ago

      create!.tap do |backup|
        backup.process!
        prune if backup.status == "ready"
      end
    end

    # What a backup file says about itself, kept on its record. Its date and
    # key read without the key; the rest needs this ZeroPaper's key. A file
    # that cannot be read, whatever is wrong with it, is kept without a key
    # id and listed as unreadable.
    def details(path)
      name = path.basename.to_s
      stat = File.lstat(path)
      envelope = Backup::Envelope.new(path.to_s)
      key = Setting.instance.backup_key_bytes
      metadata = envelope.key_id == Backup::Key.id(key) ? envelope.metadata(key) : {}
      metadata = {} unless metadata.is_a?(Hash)
      { made_at: envelope.made_at, size: stat.size, key_id: envelope.key_id, uploaded: !name.match?(MADE_HERE), made_by: metadata["made_by"],
        documents_count: metadata["documents_count"], private_documents_count: metadata["private_documents_count"] }
    rescue StandardError => error
      Rails.logger.warn("Backup #{name} cannot be read: #{error.class}")
      { made_at: stat&.mtime, size: stat&.size, key_id: nil, uploaded: !name.match?(MADE_HERE), made_by: nil, documents_count: nil, private_documents_count: nil }
    end

    def own_key_id
      Backup::Key.id(Setting.instance.backup_key_bytes)
    end

    # Adds an uploaded backup to the folder, named for when it was made so it
    # sorts with the others, and marked as uploaded so it is never pruned.
    # An encrypted backup is kept as it is, after every chunk is checked when
    # it was made with this ZeroPaper's key; the restore checks the rest. A
    # plain zip, such as an export from an older ZeroPaper, is checked and
    # encrypted with this ZeroPaper's key. A date in the future, which
    # nothing vouches for, becomes now. Returns the new record.
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
      create!(status: "ready", filename: name, **details(folder.join(name)))
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
    # another key, ones dated in the future and missing ones are left alone.
    # Nothing is pruned while the folder cannot be reached.
    def prune
      return unless reachable?

      setting = Setting.instance
      backups = stored.where(uploaded: false, key_id: own_key_id, made_at: ..Time.current, missing_at: nil).order(made_at: :desc).to_a
      return if backups.empty?

      kept = Set[backups.first]
      RETENTION.each do |period, format|
        newest_per_period = backups.uniq { |backup| backup.made_at.strftime(format) }
        kept.merge(newest_per_period.first(setting.public_send("backup_keep_#{period}")))
      end
      (backups - kept.to_a).each { |backup| backup.remove! if backup.find_file }
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
        names = [ file_name(made_at), file_name(made_at, uploaded: true) ]
        if names.any? { |name| folder.join(name).exist? } || stored.exists?(filename: names)
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

      # Writes under a hidden name, reads it back to check every chunk when
      # the key is at hand, and renames it when it is sound, so a half written
      # or damaged backup is never listed. The file must be new and must not
      # be a symlink, so a link left in a shared folder cannot make ZeroPaper
      # write somewhere else; renaming over a link replaces the link.
      def write_new(name, key:)
        begin
          FileUtils.mkdir_p(folder)
        rescue Errno::EEXIST
          raise unreachable_message
        end
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

  # The file, while it is still a regular file in the folder.
  def path
    path = self.class.folder.join(filename) if filename&.match?(FILENAME)
    path if path&.file? && !path.symlink?
  end

  # The file, or nil. A file gone from a folder that can be reached marks
  # the backup missing, and one that is back clears it. While the folder
  # cannot be reached nothing is marked.
  def find_file
    path.tap do |found|
      if found
        update!(missing_at: nil) if missing?
      elsif self.class.reachable? && !missing?
        update!(missing_at: Time.current)
      end
    end
  end

  def readable? = key_id.present?

  def missing? = missing_at.present?

  def own_key? = readable? && key_id == self.class.own_key_id

  # Deletes the file and forgets it. A backup is not forgotten while its
  # folder cannot be reached, since its file would be left behind unlisted.
  def remove!
    raise Unreachable, self.class.unreachable_message if filename && !self.class.reachable?

    path&.delete
    destroy!
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
        update!(status: "ready", filename: name, **self.class.details(self.class.folder.join(name)).merge(made_at: created_at))
      end
    end
  rescue ActiveRecord::Encryption::Errors::Decryption
    update!(status: "failed", error: "A document could not be decrypted. ZeroPaper is running with different encryption keys (SECRET_KEY_BASE) than the ones the library was saved with.")
  rescue StandardError => error
    update!(status: "failed", error: error.message.truncate(1_000))
  end
end
