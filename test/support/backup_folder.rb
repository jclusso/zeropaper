# Points BACKUP_DIR, and the scratch folder backups and restores work in, at
# fresh folders for each test.
module BackupFolder
  extend ActiveSupport::Concern

  included do
    setup do
      @backup_dir = Dir.mktmpdir
      @previous_backup_dir = Rails.configuration.x.backup_dir
      Rails.configuration.x.backup_dir = @backup_dir
      @scratch_dir = Dir.mktmpdir
      Backup::Scratch.stubs(:root).returns(Pathname(@scratch_dir))
    end

    teardown do
      Rails.configuration.x.backup_dir = @previous_backup_dir
      FileUtils.remove_entry(@backup_dir)
      FileUtils.remove_entry(@scratch_dir)
    end
  end

  private
    # A plain backup zip with a valid manifest. Entries are stored
    # uncompressed so tests can damage their bytes.
    def build_zip(entries = {}, manifest: { format: Archive::FORMAT, version: Archive::VERSION })
      Zip::OutputStream.write_buffer do |zip|
        { "manifest.json" => manifest.to_json, **entries }.each do |name, data|
          zip.put_next_entry(name, nil, nil, Zip::Entry::STORED)
          zip.write(data)
        end
      end.string
    end

    # Encrypts a zip into the backup folder and returns its file name.
    def put_sealed(zip, made_at: Time.current, key: Setting.instance.backup_key_bytes, name: Backup.file_name(made_at))
      Tempfile.create([ "backup", ".zip" ], binmode: true) do |plain|
        plain.write(zip)
        plain.flush
        File.open(File.join(@backup_dir, name), "wb") do |out|
          Backup::Envelope.seal(plain.path, out, key: key, made_at: made_at, metadata: {})
        end
      end
      name
    end

    # Stands in for a share that is not mounted: the folder's path is there
    # but is not a folder.
    def unmounted
      FileUtils.remove_entry(@backup_dir)
      File.write(@backup_dir, "")
    end

    def mounted
      File.delete(@backup_dir) if File.file?(@backup_dir)
      FileUtils.mkdir_p(@backup_dir)
    end

    def put_backup(data, name = Backup.file_name)
      File.binwrite(File.join(@backup_dir, name), data)
      name
    end

    def upload_file(data)
      Tempfile.create([ "upload", ".bin" ], binmode: true) do |file|
        file.write(data)
        file.flush
        yield file.path
      end
    end
end
