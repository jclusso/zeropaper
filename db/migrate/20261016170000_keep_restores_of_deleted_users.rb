# Restores outlive the user who ran them, as backups already do; deleting
# that user unlinks the records instead of failing on the foreign key.
class KeepRestoresOfDeletedUsers < ActiveRecord::Migration[8.1]
  def change
    change_column_null :restores, :user_id, true
    remove_foreign_key :restores, :users
    add_foreign_key :restores, :users, on_delete: :nullify
  end
end
