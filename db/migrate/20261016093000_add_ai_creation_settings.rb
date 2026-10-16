class AddAICreationSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :ai_creates_types, :boolean, null: false, default: true
    add_column :settings, :ai_creates_tags, :boolean, null: false, default: true
  end
end
