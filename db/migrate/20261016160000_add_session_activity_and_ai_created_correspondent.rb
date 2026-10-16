class AddSessionActivityAndAICreatedCorrespondent < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :last_active_at, :datetime
    add_index :sessions, :last_active_at

    add_column :documents, :ai_created_correspondent_id, :bigint
  end
end
