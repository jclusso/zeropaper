# Encryption keys derive from SECRET_KEY_BASE unless set explicitly, so a
# self-hosted install needs one secret. Losing it makes private files and
# encrypted text unreadable, so back it up with the volume.
keys = Rails.application.key_generator

Rails.application.config.active_record.encryption.tap do |encryption|
  encryption.primary_key = ENV.fetch("ENCRYPTION_PRIMARY_KEY") { keys.generate_key("zeropaper/records/primary", 32).unpack1("H*") }
  encryption.deterministic_key = ENV.fetch("ENCRYPTION_DETERMINISTIC_KEY") { keys.generate_key("zeropaper/records/deterministic", 32).unpack1("H*") }
  encryption.key_derivation_salt = ENV.fetch("ENCRYPTION_KEY_DERIVATION_SALT") { keys.generate_key("zeropaper/records/salt", 32).unpack1("H*") }
  encryption.support_unencrypted_data = false
end

Rails.application.config.x.file_encryption_key = keys.generate_key("zeropaper/files", 32)
