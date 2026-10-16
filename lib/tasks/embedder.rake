namespace :embedder do
  desc "Download the local embedding model into MODELS_DIR"
  task prefetch: :environment do
    if Embedder.downloaded?
      puts "#{Embedder::MODEL} is already in #{Informers.cache_dir}"
    else
      Embedder.download
      puts "Downloaded #{Embedder::MODEL} into #{Informers.cache_dir}"
    end
  end
end
