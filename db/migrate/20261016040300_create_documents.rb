class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.string :title
      t.date :document_date
      t.text :summary
      t.text :content

      t.boolean :private, null: false, default: false
      t.string :private_reason
      t.string :status, null: false, default: "pending"
      t.jsonb :steps, null: false, default: {}
      t.text :error

      t.boolean :needs_review, null: false, default: false
      t.jsonb :review_reasons, null: false, default: []
      t.float :confidence

      t.string :checksum, null: false
      t.string :original_filename, null: false
      t.string :content_type, null: false
      t.integer :page_count
      t.jsonb :page_record, null: false, default: {}

      t.string :source, null: false, default: "upload"
      t.string :source_detail
      t.string :text_source
      t.string :metadata_source
      t.string :ai_model

      t.references :correspondent, foreign_key: { on_delete: :nullify }
      t.references :document_type, foreign_key: { on_delete: :nullify }
      t.references :duplicate_of, foreign_key: { to_table: :documents, on_delete: :nullify }
      t.references :uploaded_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.tsvector :search_vector
      t.vector :embedding, limit: 768
      t.datetime :processed_at

      t.timestamps
    end
    add_index :documents, :checksum, unique: true
    add_index :documents, :document_date
    add_index :documents, :status
    add_index :documents, :private
    add_index :documents, :needs_review, where: "needs_review"
    add_index :documents, :search_vector, using: :gin
    add_index :documents, :title, using: :gin, opclass: :gin_trgm_ops
    add_index :documents, :embedding, using: :hnsw, opclass: :vector_cosine_ops

    create_table :taggings do |t|
      t.references :document, null: false, foreign_key: { on_delete: :cascade }
      t.references :tag, null: false, foreign_key: { on_delete: :cascade }
    end
    add_index :taggings, [ :document_id, :tag_id ], unique: true

    create_table :chunks do |t|
      t.references :document, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.integer :page_number
      t.text :content, null: false
      t.tsvector :search_vector
      t.vector :embedding, limit: 768
    end
    add_index :chunks, [ :document_id, :position ], unique: true
    add_index :chunks, :search_vector, using: :gin
    add_index :chunks, :embedding, using: :hnsw, opclass: :vector_cosine_ops
  end
end
