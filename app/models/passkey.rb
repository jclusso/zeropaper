class Passkey < ApplicationRecord
  belongs_to :user

  validates :external_id, :public_key, presence: true
  validates :name, presence: true

  def self.register(user:, credential:, challenge:, relying_party:, name:)
    webauthn_credential = relying_party.verify_registration(credential, challenge, user_verification: true)

    user.passkeys.create!(
      external_id: webauthn_credential.id,
      public_key: webauthn_credential.public_key,
      sign_count: webauthn_credential.sign_count,
      name: name.presence || "Passkey"
    )
  end

  # Returns the user the assertion belongs to, or nil when it does not verify.
  def self.authenticate(credential:, challenge:, relying_party:)
    passkey = find_by(external_id: credential["id"])
    return unless passkey

    passkey.verify(credential:, challenge:, relying_party:)
    passkey.user
  rescue WebAuthn::Error
    nil
  end

  def verify(credential:, challenge:, relying_party:)
    webauthn_credential = relying_party.verify_authentication(
      credential, challenge,
      public_key: public_key, sign_count: sign_count, user_verification: true
    )
    update!(sign_count: webauthn_credential.sign_count, last_used_at: Time.current)
  end
end
