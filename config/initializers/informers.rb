Informers.cache_dir = Rails.configuration.x.models_dir

# Fetch the embedding model when the job worker starts, so the first
# document does not wait on the download partway through processing.
SolidQueue.on_start { DownloadEmbeddingModelJob.perform_later } if defined?(SolidQueue)
