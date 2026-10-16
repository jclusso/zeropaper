class AddAutoRotatePagesToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :auto_rotate_pages, :boolean, null: false, default: true
  end
end
