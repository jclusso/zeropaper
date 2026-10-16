# Answers now record every document they carried, inherited history
# included. Older answers did not, so history treats them more strictly.
class AddProvenanceCompleteToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :provenance_complete, :boolean, default: false, null: false
  end
end
