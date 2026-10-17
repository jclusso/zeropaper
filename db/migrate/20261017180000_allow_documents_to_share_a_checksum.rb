# A document restored to its upload can be the same file as the copy it is
# being compared with, so a checksum no longer names one document.
class AllowDocumentsToShareAChecksum < ActiveRecord::Migration[8.1]
  def change
    remove_index :documents, :checksum, unique: true
    add_index :documents, :checksum
  end
end
