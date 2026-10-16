class CreateTaxonomy < ActiveRecord::Migration[8.1]
  def change
    create_table :correspondents do |t|
      t.string :name, null: false
      t.boolean :auto_match, null: false, default: true
      t.boolean :private_documents, null: false, default: false

      t.timestamps
    end
    add_index :correspondents, "lower(name)", unique: true

    create_table :document_types do |t|
      t.string :name, null: false
      t.boolean :auto_match, null: false, default: true

      t.timestamps
    end
    add_index :document_types, "lower(name)", unique: true

    create_table :tags do |t|
      t.string :name, null: false
      t.string :color, null: false, default: "slate"
      t.boolean :auto_match, null: false, default: true

      t.timestamps
    end
    add_index :tags, "lower(name)", unique: true

    create_table :rules do |t|
      t.string :name, null: false
      t.boolean :enabled, null: false, default: true
      t.integer :position, null: false, default: 0
      t.string :match_mode, null: false, default: "all"
      t.jsonb :conditions, null: false, default: []
      t.references :correspondent, foreign_key: { on_delete: :nullify }
      t.references :document_type, foreign_key: { on_delete: :nullify }
      t.bigint :tag_ids, array: true, null: false, default: []
      t.boolean :mark_private, null: false, default: false

      t.timestamps
    end
  end
end
