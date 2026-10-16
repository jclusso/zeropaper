class Passkeys::ChallengesController < ApplicationController
  include WebAuthnRelyingParty

  def create
    options = relying_party.options_for_registration(
      user: { id: Current.user.webauthn_id, name: Current.user.email_address, display_name: Current.user.name },
      exclude: Current.user.passkeys.pluck(:external_id),
      authenticator_selection: { resident_key: "required", user_verification: "required" }
    )
    session[:passkey_registration_challenge] = options.challenge
    render json: options
  end
end
