# How each page looks, so rescans OCR reads differently still match as
# duplicates.
class AddPageHashesToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :page_hashes, :string, array: true, default: [], null: false
  end
end
