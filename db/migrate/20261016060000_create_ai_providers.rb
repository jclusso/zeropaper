class CreateAIProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_providers do |t|
      t.string :kind, null: false
      t.string :name, null: false
      t.text :api_key
      t.string :base_url

      t.timestamps
    end

    change_table :settings do |t|
      t.boolean :ai_enabled, null: false, default: false
      t.datetime :setup_completed_at
      t.references :extraction_provider, foreign_key: { to_table: :ai_providers, on_delete: :nullify }
      t.references :research_provider, foreign_key: { to_table: :ai_providers, on_delete: :nullify }
      t.references :vision_provider, foreign_key: { to_table: :ai_providers, on_delete: :nullify }
      t.rename :vision_ocr_model, :vision_model
    end
    change_column_null :settings, :extraction_model, true
    change_column_null :settings, :research_model, true
    change_column_null :settings, :vision_model, true
    change_column_default :settings, :extraction_model, from: "gpt-5.6-luna", to: nil
    change_column_default :settings, :research_model, from: "gpt-5.6", to: nil
    change_column_default :settings, :vision_model, from: "gpt-5.6-luna", to: nil
    change_column_default :settings, :ocr_provider, from: "llm_vision", to: "tesseract"

    # Keys entered before providers existed become providers.
    reversible do |direction|
      direction.up { MoveKeysToProviders.new.run }
    end

    remove_column :settings, :openai_api_key, :text
    remove_column :settings, :mistral_api_key, :text
  end

  class MoveKeysToProviders
    class Setting < ActiveRecord::Base
      self.table_name = "settings"
      encrypts :openai_api_key, :mistral_api_key
    end

    class AiProvider < ActiveRecord::Base
      self.table_name = "ai_providers"
      encrypts :api_key
    end

    def run
      Setting.reset_column_information
      Setting.find_each do |setting|
        if setting.openai_api_key.present?
          openai = AiProvider.create!(kind: "openai", name: "OpenAI", api_key: setting.openai_api_key)
          setting.update_columns(ai_enabled: true, setup_completed_at: Time.current,
            extraction_provider_id: openai.id, research_provider_id: openai.id, vision_provider_id: openai.id)
        end
        if setting.mistral_api_key.present?
          AiProvider.create!(kind: "mistral", name: "Mistral", api_key: setting.mistral_api_key)
        end
        if setting.ocr_provider == "llm_vision" && setting.openai_api_key.blank?
          setting.update_columns(ocr_provider: "tesseract")
        end
        if setting.ocr_provider == "mistral" && setting.mistral_api_key.blank?
          setting.update_columns(ocr_provider: "tesseract")
        end
        setting.update_columns(setup_completed_at: Time.current) if setting.setup_completed_at.nil?
      end
    end
  end
end
