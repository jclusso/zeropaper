# Tag and type names ("Tax", "Invoice") appear in too many documents to match
# by name. Correspondent names are specific enough, so they keep matching.
class TurnOffNameMatchingForTagsAndTypes < ActiveRecord::Migration[8.1]
  def change
    change_column_default :tags, :auto_match, from: true, to: false
    change_column_default :document_types, :auto_match, from: true, to: false

    reversible do |direction|
      direction.up do
        execute "UPDATE tags SET auto_match = false"
        execute "UPDATE document_types SET auto_match = false"
      end
    end
  end
end
