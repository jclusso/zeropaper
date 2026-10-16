class AddUsedDocumentIdsToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :used_document_ids, :integer, array: true, default: [], null: false
  end
end
