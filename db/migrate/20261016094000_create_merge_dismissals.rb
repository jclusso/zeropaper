# Similar-name suggestions someone said are not the same thing.
class CreateMergeDismissals < ActiveRecord::Migration[8.1]
  def change
    create_table :merge_dismissals do |t|
      t.string :kind, null: false
      t.bigint :first_id, null: false
      t.bigint :second_id, null: false

      t.timestamps
    end
    add_index :merge_dismissals, [ :kind, :first_id, :second_id ], unique: true
  end
end
