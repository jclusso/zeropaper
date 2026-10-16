class CreateArchives < ActiveRecord::Migration[8.1]
  def change
    create_table :exports do |t|
      t.references :user, null: false, foreign_key: true
      t.boolean :include_private, null: false, default: true
      t.string :status, null: false, default: "pending"
      t.integer :documents_count
      t.text :error

      t.timestamps
    end

    create_table :restores do |t|
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.integer :restored_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.text :error

      t.timestamps
    end
  end
end
