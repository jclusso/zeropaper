class AddStraightenPagesToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :straighten_pages, :boolean, default: true, null: false
  end
end
