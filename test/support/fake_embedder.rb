# Deterministic stand-in for the local embedding model so tests never
# download it: the same text always maps to the same unit vector.
module FakeEmbedder
  def embed_documents(texts)
    texts.map { |text| FakeEmbedder.vector_for(text) }
  end

  def embed_query(text)
    FakeEmbedder.vector_for(text)
  end

  def self.vector_for(text)
    random = Random.new(Digest::SHA256.hexdigest(text.to_s).to_i(16) % (2**63))
    values = Array.new(Embedder::DIMENSIONS) { random.rand - 0.5 }
    norm = Math.sqrt(values.sum { |value| value * value })
    values.map { |value| value / norm }
  end
end

Embedder.singleton_class.prepend(FakeEmbedder)
