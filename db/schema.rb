# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_16_180000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "vector"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ai_providers", force: :cascade do |t|
    t.string "kind", null: false
    t.string "name", null: false
    t.text "api_key"
    t.string "base_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "backups", force: :cascade do |t|
    t.bigint "user_id"
    t.string "filename"
    t.string "status", default: "pending", null: false
    t.integer "documents_count"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_backups_on_user_id"
  end

  create_table "chunks", force: :cascade do |t|
    t.bigint "document_id", null: false
    t.integer "position", null: false
    t.integer "page_number"
    t.text "content", null: false
    t.tsvector "search_vector"
    t.vector "embedding", limit: 768
    t.index ["document_id", "position"], name: "index_chunks_on_document_id_and_position", unique: true
    t.index ["document_id"], name: "index_chunks_on_document_id"
    t.index ["embedding"], name: "index_chunks_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["search_vector"], name: "index_chunks_on_search_vector", using: :gin
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_conversations_on_user_id"
  end

  create_table "correspondents", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "auto_match", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_correspondents_on_lower_name", unique: true
  end

  create_table "document_types", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "auto_match", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_document_types_on_lower_name", unique: true
  end

  create_table "documents", force: :cascade do |t|
    t.string "title"
    t.date "document_date"
    t.text "summary"
    t.text "content"
    t.boolean "private", default: false, null: false
    t.string "private_reason"
    t.string "status", default: "pending", null: false
    t.jsonb "steps", default: {}, null: false
    t.text "error"
    t.boolean "needs_review", default: false, null: false
    t.jsonb "review_reasons", default: [], null: false
    t.float "confidence"
    t.string "checksum", null: false
    t.string "original_filename", null: false
    t.string "content_type", null: false
    t.integer "page_count"
    t.jsonb "page_record", default: {}, null: false
    t.string "source", default: "upload", null: false
    t.string "source_detail"
    t.string "text_source"
    t.string "metadata_source"
    t.string "ai_model"
    t.bigint "correspondent_id"
    t.bigint "document_type_id"
    t.bigint "duplicate_of_id"
    t.bigint "uploaded_by_id"
    t.tsvector "search_vector"
    t.vector "embedding", limit: 768
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "processing_run"
    t.bigint "ai_created_correspondent_id"
    t.index ["checksum"], name: "index_documents_on_checksum", unique: true
    t.index ["correspondent_id"], name: "index_documents_on_correspondent_id"
    t.index ["document_date"], name: "index_documents_on_document_date"
    t.index ["document_type_id"], name: "index_documents_on_document_type_id"
    t.index ["duplicate_of_id"], name: "index_documents_on_duplicate_of_id"
    t.index ["embedding"], name: "index_documents_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["needs_review"], name: "index_documents_on_needs_review", where: "needs_review"
    t.index ["private"], name: "index_documents_on_private"
    t.index ["search_vector"], name: "index_documents_on_search_vector", using: :gin
    t.index ["status"], name: "index_documents_on_status"
    t.index ["title"], name: "index_documents_on_title", opclass: :gin_trgm_ops, using: :gin
    t.index ["uploaded_by_id"], name: "index_documents_on_uploaded_by_id"
  end

  create_table "merge_dismissals", force: :cascade do |t|
    t.string "kind", null: false
    t.bigint "first_id", null: false
    t.bigint "second_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind", "first_id", "second_id"], name: "index_merge_dismissals_on_kind_and_first_id_and_second_id", unique: true
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.string "role", null: false
    t.text "content", default: "", null: false
    t.string "status", default: "complete", null: false
    t.jsonb "steps", default: [], null: false
    t.jsonb "cited_document_ids", default: [], null: false
    t.integer "private_match_ids", default: [], null: false, array: true
    t.string "model"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "used_document_ids", default: [], null: false, array: true
    t.boolean "provenance_complete", default: false, null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
  end

  create_table "passkeys", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "external_id", null: false
    t.text "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.string "name", null: false
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_passkeys_on_external_id", unique: true
    t.index ["user_id"], name: "index_passkeys_on_user_id"
  end

  create_table "restores", force: :cascade do |t|
    t.bigint "user_id"
    t.string "status", default: "pending", null: false
    t.integer "restored_count", default: 0, null: false
    t.integer "skipped_count", default: 0, null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "filename"
    t.string "key"
    t.index ["user_id"], name: "index_restores_on_user_id"
  end

  create_table "rules", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "enabled", default: true, null: false
    t.integer "position", default: 0, null: false
    t.string "match_mode", default: "all", null: false
    t.jsonb "conditions", default: [], null: false
    t.bigint "correspondent_id"
    t.bigint "document_type_id"
    t.bigint "tag_ids", default: [], null: false, array: true
    t.boolean "mark_private", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["correspondent_id"], name: "index_rules_on_correspondent_id"
    t.index ["document_type_id"], name: "index_rules_on_document_type_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_active_at"
    t.index ["last_active_at"], name: "index_sessions_on_last_active_at"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.string "extraction_model"
    t.string "research_model"
    t.string "vision_model"
    t.string "local_ocr_provider", default: "tesseract", null: false
    t.string "docling_url"
    t.boolean "searchable_pdf", default: true, null: false
    t.boolean "blank_page_detection", default: true, null: false
    t.boolean "blank_page_ai_check", default: false, null: false
    t.boolean "always_require_review", default: false, null: false
    t.float "review_confidence_threshold", default: 0.7, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "ai_enabled", default: false, null: false
    t.datetime "setup_completed_at"
    t.bigint "extraction_provider_id"
    t.bigint "research_provider_id"
    t.bigint "vision_provider_id"
    t.boolean "auto_rotate_pages", default: true, null: false
    t.boolean "ingest_enabled", default: true, null: false
    t.boolean "ai_creates_types", default: true, null: false
    t.boolean "ai_creates_tags", default: true, null: false
    t.boolean "backup_enabled", default: false, null: false
    t.string "backup_frequency", default: "daily", null: false
    t.integer "backup_keep_daily", default: 7, null: false
    t.integer "backup_keep_weekly", default: 4, null: false
    t.integer "backup_keep_monthly", default: 12, null: false
    t.integer "backup_keep_yearly", default: 2, null: false
    t.string "backup_key"
    t.datetime "backup_key_downloaded_at"
    t.index ["extraction_provider_id"], name: "index_settings_on_extraction_provider_id"
    t.index ["research_provider_id"], name: "index_settings_on_research_provider_id"
    t.index ["vision_provider_id"], name: "index_settings_on_vision_provider_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.binary "payload", null: false
    t.datetime "created_at", null: false
    t.bigint "channel_hash", null: false
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.binary "key", null: false
    t.binary "value", null: false
    t.datetime "created_at", null: false
    t.bigint "key_hash", null: false
    t.integer "byte_size", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.string "description"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_failure"
    t.text "metadata"
    t.integer "total_jobs", default: 0, null: false
    t.integer "completed_jobs", default: 0, null: false
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "enqueued_at"
    t.datetime "finished_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "batch_id"
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "taggings", force: :cascade do |t|
    t.bigint "document_id", null: false
    t.bigint "tag_id", null: false
    t.index ["document_id", "tag_id"], name: "index_taggings_on_document_id_and_tag_id", unique: true
    t.index ["document_id"], name: "index_taggings_on_document_id"
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
  end

  create_table "tags", force: :cascade do |t|
    t.string "name", null: false
    t.string "color", default: "slate", null: false
    t.boolean "auto_match", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_tags_on_lower_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "name", null: false
    t.boolean "admin", default: false, null: false
    t.string "webauthn_id", null: false
    t.string "theme", default: "system", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["webauthn_id"], name: "index_users_on_webauthn_id", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "backups", "users", on_delete: :nullify
  add_foreign_key "chunks", "documents", on_delete: :cascade
  add_foreign_key "conversations", "users"
  add_foreign_key "documents", "correspondents", on_delete: :nullify
  add_foreign_key "documents", "document_types", on_delete: :nullify
  add_foreign_key "documents", "documents", column: "duplicate_of_id", on_delete: :nullify
  add_foreign_key "documents", "users", column: "uploaded_by_id", on_delete: :nullify
  add_foreign_key "messages", "conversations", on_delete: :cascade
  add_foreign_key "passkeys", "users"
  add_foreign_key "restores", "users", on_delete: :nullify
  add_foreign_key "rules", "correspondents", on_delete: :nullify
  add_foreign_key "rules", "document_types", on_delete: :nullify
  add_foreign_key "sessions", "users"
  add_foreign_key "settings", "ai_providers", column: "extraction_provider_id", on_delete: :nullify
  add_foreign_key "settings", "ai_providers", column: "research_provider_id", on_delete: :nullify
  add_foreign_key "settings", "ai_providers", column: "vision_provider_id", on_delete: :nullify
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "taggings", "documents", on_delete: :cascade
  add_foreign_key "taggings", "tags", on_delete: :cascade
end
