# "Documents from this correspondent are private" becomes an ordinary rule, so
# privacy has one mechanism. Each private correspondent gets an enabled rule
# that marks documents private when their text contains its name, unless an
# equivalent rule already exists. The rule also files them under it.
class MovePrivateCorrespondentsToRules < ActiveRecord::Migration[8.1]
  class Correspondent < ActiveRecord::Base
    self.table_name = "correspondents"
  end

  class Rule < ActiveRecord::Base
    self.table_name = "rules"
  end

  def up
    Correspondent.where(private_documents: true).find_each do |correspondent|
      next if equivalent_rule?(correspondent.name)

      Rule.create!(name: "Private: #{correspondent.name}", enabled: true, match_mode: "all",
        conditions: [ { "field" => "content", "operator" => "phrase", "value" => correspondent.name } ],
        correspondent_id: correspondent.id, mark_private: true)
    end

    remove_column :correspondents, :private_documents
  end

  def down
    add_column :correspondents, :private_documents, :boolean, default: false, null: false
  end

  private
    # An enabled rule that marks documents private whenever the text contains
    # the name, on its own or as one of several "any" conditions.
    def equivalent_rule?(name)
      Rule.where(enabled: true, mark_private: true).any? do |rule|
        conditions = Array(rule.conditions)
        phrase = conditions.any? do |condition|
          condition["field"] == "content" && condition["operator"] == "phrase" && condition["value"].to_s.squish.casecmp?(name.squish)
        end
        phrase && (conditions.size == 1 || rule.match_mode == "any")
      end
    end
end
