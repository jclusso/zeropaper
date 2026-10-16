# Rails.cache for values made from document contents, such as page images
# and spreadsheet rows. The cache lives in the database, so values are
# encrypted the way document text is.
module SealedCache
  extend self

  def fetch(key, expires_in:)
    sealed = Rails.cache.fetch(key, expires_in: expires_in) { encryptor.encrypt(yield) }
    encryptor.decrypt(sealed)
  end

  private
    def encryptor
      ActiveRecord::Encryption.encryptor
    end
end
