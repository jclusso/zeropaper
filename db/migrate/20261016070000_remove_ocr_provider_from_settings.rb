# Scans are read by the vision task's model when AI is on, and by the local
# engine otherwise, so there is no separate engine choice any more.
class RemoveOcrProviderFromSettings < ActiveRecord::Migration[8.1]
  def change
    remove_column :settings, :ocr_provider, :string, null: false, default: "tesseract"
  end
end
