class Sessions::PasskeysController < ApplicationController
  include WebAuthnRelyingParty

  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, with: -> { render json: { error: "Try again later." }, status: :too_many_requests }

  def create
    challenge = session.delete(:passkey_authentication_challenge)
    user = challenge && Passkey.authenticate(credential: credential_params, challenge: challenge, relying_party: relying_party)

    if user
      start_new_session_for user
      render json: { location: after_authentication_url }
    else
      render json: { error: "That passkey was not recognized." }, status: :unprocessable_entity
    end
  end
end
