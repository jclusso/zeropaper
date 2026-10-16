class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :name, null: false
      t.boolean :admin, null: false, default: false
      t.string :webauthn_id, null: false
      t.string :theme, null: false, default: "system"

      t.timestamps
    end
    add_index :users, :email_address, unique: true
    add_index :users, :webauthn_id, unique: true
  end
end
