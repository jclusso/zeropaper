# New document types and tags match documents that mention their name, like
# correspondents already do. Existing ones keep their setting.
class AutoMatchTypesAndTagsByDefault < ActiveRecord::Migration[8.1]
  def change
    change_column_default :document_types, :auto_match, from: false, to: true
    change_column_default :tags, :auto_match, from: false, to: true
  end
end
