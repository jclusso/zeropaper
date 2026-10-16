class AddIngestFolderToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :ingest_enabled, :boolean, null: false, default: true
    add_column :settings, :ingest_dir, :string
  end
end
