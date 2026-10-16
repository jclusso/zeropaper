require "active_storage/service/disk_service"

# Private documents' files used to be sealed with AES-256-GCM on a separate
# "_private" disk service. Every file now lives unencrypted on the one disk
# service, so this decrypts each sealed file into it. The upload checks the
# blob's checksum, and the sealed copy is removed only after the blob is
# saved, so a failed run can simply be run again.
class DecryptPrivateFiles < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  IV_LENGTH = 12
  TAG_LENGTH = 16

  class Blob < ActiveRecord::Base
    self.table_name = "active_storage_blobs"
  end

  def up
    sealed = ActiveStorage::Service::DiskService.new(root: Rails.root.join("storage/private"))
    key = Rails.application.key_generator.generate_key("zeropaper/files", 32)

    Blob.where("service_name LIKE ?", "%\\_private").find_each do |blob|
      service_name = blob.service_name.delete_suffix("_private")
      path = sealed.path_for(blob.key)

      if File.exist?(path)
        ActiveStorage::Blob.services.fetch(service_name).upload(blob.key, StringIO.new(unseal(File.binread(path), key)), checksum: blob.checksum)
      else
        # Still moved, since the private service no longer exists to look it up.
        say "Blob #{blob.id} has no file at #{path}"
      end
      blob.update_columns(service_name: service_name)
      File.delete(path) if File.exist?(path)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private
    def unseal(sealed, key)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = key
      cipher.iv = sealed.byteslice(0, IV_LENGTH)
      cipher.auth_tag = sealed.byteslice(IV_LENGTH, TAG_LENGTH)
      cipher.update(sealed.byteslice((IV_LENGTH + TAG_LENGTH)..)) + cipher.final
    end
end
