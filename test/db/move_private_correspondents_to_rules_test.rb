require "test_helper"
require Rails.root.join("db/migrate/20261016130100_move_private_correspondents_to_rules")

# Runs the migration inside the test transaction; Postgres rolls the column
# changes back with it.
class MovePrivateCorrespondentsToRulesTest < ActiveSupport::TestCase
  setup do
    ActiveRecord::Migration.suppress_messages do
      ActiveRecord::Migration.add_column :correspondents, :private_documents, :boolean, default: false, null: false
    end
  end

  teardown do
    ActiveRecord::Base.connection.clear_cache!
    Correspondent.reset_column_information
  end

  test "each private correspondent becomes a rule that marks mentions private" do
    hospital = Correspondent.create!(name: "Harbor Hospital")
    Correspondent.where(id: [ hospital.id, correspondents(:city_clinic).id ]).update_all(private_documents: true)

    assert_difference -> { Rule.count }, 1 do
      ActiveRecord::Migration.suppress_messages { MovePrivateCorrespondentsToRules.new.migrate(:up) }
    end
    # The column change invalidates prepared statements on this connection.
    ActiveRecord::Base.connection.clear_cache!
    Correspondent.reset_column_information

    rule = Rule.find_by!(name: "Private: Harbor Hospital")
    assert rule.enabled?
    assert rule.mark_private?
    assert_equal hospital, rule.correspondent
    assert rule.matches?(Document.new, text: "Results from Harbor Hospital")
    assert_equal 1, Rule.where(correspondent: correspondents(:city_clinic), mark_private: true).count, "the existing equivalent rule is kept, not duplicated"
    refute_includes Correspondent.column_names, "private_documents"
  end
end
