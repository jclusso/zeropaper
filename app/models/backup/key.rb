# The key backups are encrypted with: 32 random bytes, written as
# "zpkey-" and URL-safe Base64 so it can be saved, printed or pasted. It is
# kept encrypted in Settings and has nothing to do with SECRET_KEY_BASE, so a
# backup and this key are enough to restore anywhere.
module Backup::Key
  PATTERN = /zpkey-([A-Za-z0-9_-]{43})/

  module_function

  def generate
    encode(SecureRandom.random_bytes(32))
  end

  def encode(bytes)
    "zpkey-#{Base64.urlsafe_encode64(bytes, padding: false)}"
  end

  # The raw key from a key file or pasted text, or nil.
  def parse(text)
    match = text.to_s.match(PATTERN) or return
    Base64.urlsafe_decode64(match[1])
  rescue ArgumentError
    nil
  end

  # Short and safe to show: tells keys apart without revealing them.
  def id(bytes)
    Digest::SHA256.hexdigest(bytes).first(8)
  end

  def file_contents(text)
    <<~TEXT
      ZeroPaper backup key #{id(parse(text))}

      Backups from this ZeroPaper are encrypted with this key and cannot be
      restored without it. Keep it somewhere safe and apart from the backups.

      #{text}
    TEXT
  end
end
