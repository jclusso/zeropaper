class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.text :openai_api_key
      t.text :mistral_api_key
      t.string :extraction_model, null: false, default: "gpt-5.6-luna"
      t.string :research_model, null: false, default: "gpt-5.6"
      t.string :vision_ocr_model, null: false, default: "gpt-5.6-luna"

      t.string :ocr_provider, null: false, default: "llm_vision"
      t.string :local_ocr_provider, null: false, default: "tesseract"
      t.string :docling_url
      t.boolean :searchable_pdf, null: false, default: true

      t.boolean :blank_page_detection, null: false, default: true
      t.boolean :blank_page_ai_check, null: false, default: false

      t.boolean :always_require_review, null: false, default: false
      t.float :review_confidence_threshold, null: false, default: 0.7

      t.timestamps
    end
  end
end
