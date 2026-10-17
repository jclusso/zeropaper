# Backups are listed from their records instead of the folder, so each record
# keeps what the folder listing used to read from the file. Records are made
# for the files already in the folder; if the folder cannot be read now, run
# bin/rails backups:record_existing_files once it can.
class KeepBackupDetails < ActiveRecord::Migration[8.1]
  def up
    change_table :backups, bulk: true do |t|
      t.datetime :made_at
      t.bigint :size
      t.string :key_id
      t.string :made_by
      t.integer :private_documents_count
      t.boolean :uploaded, default: false, null: false
    end
    add_index :backups, :filename, unique: true, where: "status = 'ready'"

    Backup.reset_column_information
    begin
      Backup.record_existing_files
    rescue StandardError => error
      say "Run bin/rails backups:record_existing_files once the backup folder can be read: #{error.message}"
    end
  end

  def down
    remove_index :backups, :filename
    change_table :backups, bulk: true do |t|
      t.remove :made_at, :size, :key_id, :made_by, :private_documents_count, :uploaded
    end
  end
end
