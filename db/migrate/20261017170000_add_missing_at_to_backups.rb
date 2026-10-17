class AddMissingAtToBackups < ActiveRecord::Migration[8.1]
  def change
    add_column :backups, :missing_at, :datetime
  end
end
