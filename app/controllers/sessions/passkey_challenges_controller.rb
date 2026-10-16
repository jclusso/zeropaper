class Sessions::PasskeyChallengesController < ApplicationController
  include WebAuthnRelyingParty

  allow_unauthenticated_access
  rate_limit to: 20, within: 3.minutes

  def create
    options = relying_party.options_for_authentication(user_verification: "required")
    session[:passkey_authentication_challenge] = options.challenge
    render json: options
  end
end
