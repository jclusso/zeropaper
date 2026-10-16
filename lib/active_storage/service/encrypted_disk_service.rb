require "active_storage/service/disk_service"

module ActiveStorage
  # Disk storage that keeps only ciphertext on the volume. Private documents
  # live here: every file is sealed with AES-256-GCM under a key derived from
  # the app's secret, so a copied volume or backup reveals nothing without it.
  class Service::EncryptedDiskService < Service::DiskService
    CIPHER = "aes-256-gcm".freeze
    IV_LENGTH = 12
    TAG_LENGTH = 16

    def upload(key, io, checksum: nil, **)
      instrument :upload, key: key, checksum: checksum do
        data = io.read
        verify_checksum(key, data, checksum)
        File.binwrite(make_path_for(key), seal(data))
      end
    end

    def download(key, &block)
      data = instrument(:download, key: key) { open_sealed(key) }
      if block_given?
        StringIO.new(data).each(5.megabytes, &block)
      else
        data
      end
    end

    def download_chunk(key, range)
      instrument :download_chunk, key: key, range: range do
        open_sealed(key).byteslice(range)
      end
    end

    def compose(...)
      raise NotImplementedError, "encrypted files cannot be composed"
    end

    private
      def open_sealed(key)
        unseal(File.binread(path_for(key)))
      rescue Errno::ENOENT
        raise ActiveStorage::FileNotFoundError
      end

      def seal(data)
        cipher = OpenSSL::Cipher.new(CIPHER).encrypt
        cipher.key = encryption_key
        iv = cipher.random_iv
        ciphertext = cipher.update(data) + cipher.final
        iv + cipher.auth_tag + ciphertext
      end

      def unseal(sealed)
        cipher = OpenSSL::Cipher.new(CIPHER).decrypt
        cipher.key = encryption_key
        cipher.iv = sealed.byteslice(0, IV_LENGTH)
        cipher.auth_tag = sealed.byteslice(IV_LENGTH, TAG_LENGTH)
        cipher.update(sealed.byteslice((IV_LENGTH + TAG_LENGTH)..)) + cipher.final
      end

      def encryption_key
        Rails.application.config.x.file_encryption_key
      end

      def verify_checksum(key, data, checksum)
        return unless checksum
        return if OpenSSL::Digest::MD5.base64digest(data) == checksum

        raise ActiveStorage::IntegrityError
      end
  end
end
