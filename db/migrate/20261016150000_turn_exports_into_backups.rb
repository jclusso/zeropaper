# Exports become backups: self-contained encrypted zips in one folder (BACKUP_DIR),
# made on demand or on a schedule and restored from that folder. Old exports
# and uploaded restore archives lived in Active Storage and are removed. The
# ingest and backup folders are now chosen by mounting them, not in Settings.
class TurnExportsIntoBackups < ActiveRecord::Migration[8.1]
  def up
    # Export no longer exists, so the attachments are removed without loading
    # their records, then their blobs and files.
    attachments = ActiveStorage::Attachment.where(record_type: %w[Export Restore])
    blob_ids = attachments.pluck(:blob_id)
    attachments.delete_all
    ActiveStorage::Blob.where(id: blob_ids).find_each(&:purge)
    drop_table :exports

    create_table :backups do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :filename
      t.string :status, null: false, default: "pending"
      t.integer :documents_count
      t.text :error
      t.timestamps
    end

    change_table :restores, bulk: true do |t|
      t.string :filename
      t.string :key
    end

    change_table :settings, bulk: true do |t|
      t.remove :ingest_dir
      t.boolean :backup_enabled, null: false, default: false
      t.string :backup_frequency, null: false, default: "daily"
      t.integer :backup_keep_daily, null: false, default: 7
      t.integer :backup_keep_weekly, null: false, default: 4
      t.integer :backup_keep_monthly, null: false, default: 12
      t.integer :backup_keep_yearly, null: false, default: 2
      t.string :backup_key
      t.datetime :backup_key_downloaded_at
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
