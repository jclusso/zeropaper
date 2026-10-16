# Local text embeddings, computed in this process. The model downloads once
# into MODELS_DIR, from the worker at start or `bin/rails embedder:prefetch`,
# never partway through processing; after that no text leaves the machine,
# so every document, private or not, shares one search space.
module Embedder
  MODEL = "Snowflake/snowflake-arctic-embed-m-v1.5".freeze
  # The repository commit the files come from, so a change upstream cannot
  # swap the model, or its dimensions, under the stored embeddings.
  REVISION = "e58a8f756156a1293d763f17e3aae643474e9b8a".freeze
  DIMENSIONS = 768
  QUERY_PREFIX = "Represent this sentence for searching relevant passages: ".freeze
  BATCH_SIZE = 16
  # What the embedding pipeline loads from the model's repository.
  FILES = %w[config.json tokenizer.json tokenizer_config.json onnx/model.onnx].freeze
  LOCK_FILE = ".embedder.lock".freeze
  MUTEX = Mutex.new

  # Raised when text needs embedding before the model is on disk. The
  # download is queued, so retrying once it finishes works.
  class ModelMissing < StandardError; end

  extend self

  # Fetches the model files without loading the model, so the job worker
  # can do it at start without holding the model in memory. The file lock
  # keeps two processes from writing the same file at once.
  def download
    with_file_lock do
      FILES.each { |file| Informers::Utils::Hub.get_model_file(MODEL, file, revision: REVISION) }
      raise "The search model download did not complete." unless downloaded?
    end
    FILES
  end

  def downloaded?
    FILES.all? { |file| File.exist?(File.join(Informers.cache_dir, MODEL, REVISION, file)) }
  end

  def embed_documents(texts)
    texts.each_slice(BATCH_SIZE).flat_map { |batch| run(batch) }
  end

  def embed_query(text)
    run([ QUERY_PREFIX + text ]).first
  end

  private
    def run(texts)
      return [] if texts.empty?

      MUTEX.synchronize { pipeline.(texts, model_output: "sentence_embedding", pooling: "none") }
    end

    # Loads from disk only. A missing model queues the download and fails
    # this step rather than fetching it now.
    def pipeline
      @pipeline ||= begin
        unless downloaded?
          DownloadEmbeddingModelJob.perform_later
          raise ModelMissing, "The search model has not finished downloading. Retry once it is ready."
        end

        with_file_lock { Informers.pipeline("embedding", MODEL, revision: REVISION, local_files_only: true) }
      end
    end

    def with_file_lock
      FileUtils.mkdir_p(Informers.cache_dir)
      File.open(File.join(Informers.cache_dir, LOCK_FILE), File::RDWR | File::CREAT, 0o644) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      end
    end
end
