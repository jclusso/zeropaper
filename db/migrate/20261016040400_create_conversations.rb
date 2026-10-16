class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false

      t.timestamps
    end

    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.string :role, null: false
      t.text :content, null: false, default: ""
      t.string :status, null: false, default: "complete"
      t.jsonb :steps, null: false, default: []
      t.jsonb :cited_document_ids, null: false, default: []
      t.integer :private_match_ids, array: true, null: false, default: []
      t.string :model

      t.timestamps
    end
  end
end
