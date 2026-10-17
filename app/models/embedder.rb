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
  # What the embedding pipeline loads from the model's repository, with the
  # SHA-256 of each file at REVISION, so a truncated or altered download is
  # caught and fetched again.
  CHECKSUMS = {
    "config.json" => "d2dddc06af0aeeb7fd3289a3dee1ac76dce0c3df2467cadd26f5f731f8d7919b",
    "tokenizer.json" => "91f1def9b9391fdabe028cd3f3fcc4efd34e5d1f08c3bf2de513ebb5911a1854",
    "tokenizer_config.json" => "0e83e9d7206b3ade43f8f2aeef523cf5d5b4a25b67af21b273de21972c0f58b7",
    "onnx/model.onnx" => "bc6f7662487a0796e6f86229c8e5c3ab2f7059e08e0bb2f524125273f72171c4"
  }.freeze
  FILES = CHECKSUMS.keys.freeze
  LOCK_FILE = ".embedder.lock".freeze
  # Written once every file matched its checksum, so checking for the model
  # does not read half a gigabyte each time.
  VERIFIED_FILE = ".verified".freeze
  MUTEX = Mutex.new

  # Raised when text needs embedding before the model is on disk. The
  # download is queued, and documents waiting on it are indexed once it
  # finishes.
  class ModelMissing < StandardError; end

  extend self

  # Fetches the model files without loading the model, so the job worker
  # can do it at start without holding the model in memory. The file lock
  # keeps two processes from writing the same file at once. A file that
  # does not match its checksum is fetched again, and the copy from before
  # the model was pinned is removed once this one is complete.
  def download
    with_file_lock do
      CHECKSUMS.each do |file, checksum|
        path = model_path(file)
        next if intact?(path, checksum)

        FileUtils.rm_f(path)
        Informers::Utils::Hub.get_model_file(MODEL, file, revision: REVISION)
        next if intact?(path, checksum)

        FileUtils.rm_f(path)
        raise "The search model download did not complete: #{file} is missing or damaged."
      end
      FileUtils.touch(model_path(VERIFIED_FILE))
      remove_unpinned_copy
    end
    FILES
  end

  def downloaded?
    File.exist?(model_path(VERIFIED_FILE)) && FILES.all? { |file| File.exist?(model_path(file)) }
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
          raise ModelMissing, "The search model has not finished downloading."
        end

        with_file_lock { Informers.pipeline("embedding", MODEL, revision: REVISION, local_files_only: true) }
      end
    end

    def model_path(file)
      File.join(Informers.cache_dir, MODEL, REVISION, file)
    end

    def intact?(path, checksum)
      File.exist?(path) && Digest::SHA256.file(path).hexdigest == checksum
    end

    # Before the model was pinned its files sat directly in the model's
    # folder. Only those files go; the pinned revision and anything else in
    # MODELS_DIR stay.
    def remove_unpinned_copy
      folder = File.join(Informers.cache_dir, MODEL)
      FILES.each { |file| FileUtils.rm_f(File.join(folder, file)) }
      onnx = File.join(folder, "onnx")
      Dir.rmdir(onnx) if Dir.exist?(onnx) && Dir.empty?(onnx)
    end

    def with_file_lock
      FileUtils.mkdir_p(Informers.cache_dir)
      File.open(File.join(Informers.cache_dir, LOCK_FILE), File::RDWR | File::CREAT, 0o644) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      end
    end
end
