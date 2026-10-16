# Local text embeddings, computed in this process. The model downloads once
# into MODELS_DIR; after that no text leaves the machine, so every document,
# private or not, shares one search space.
module Embedder
  MODEL = "Snowflake/snowflake-arctic-embed-m-v1.5".freeze
  DIMENSIONS = 768
  QUERY_PREFIX = "Represent this sentence for searching relevant passages: ".freeze
  BATCH_SIZE = 16
  # What the embedding pipeline loads from the model's repository.
  FILES = %w[config.json tokenizer.json tokenizer_config.json onnx/model.onnx].freeze

  extend self

  # Fetches the model files without loading the model, so the job worker
  # can do it at start without holding the model in memory.
  def download
    FILES.each { |file| Informers::Utils::Hub.get_model_file(MODEL, file) }
  end

  def downloaded?
    FILES.all? { |file| File.exist?(File.join(Informers.cache_dir, MODEL, file)) }
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

      mutex.synchronize { pipeline.(texts, model_output: "sentence_embedding", pooling: "none") }
    end

    def pipeline
      @pipeline ||= Informers.pipeline("embedding", MODEL)
    end

    def mutex
      @mutex ||= Mutex.new
    end
end
