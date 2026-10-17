class Passkeys::ChallengesController < ApplicationController
  include WebAuthnRelyingParty

  rate_limit to: 10, within: 3.minutes, with: -> { render json: { error: "Try again later." }, status: :too_many_requests }

  # A passkey signs in without the password, so adding one needs the current
  # password, like changing the email address or the password does.
  def create
    password = params[:current_password].to_s
    unless Current.user.authenticate(password)
      return render json: { error: password.blank? ? "Enter your current password to add a passkey." : "Your current password is incorrect." },
        status: :unprocessable_entity
    end

    options = relying_party.options_for_registration(
      user: { id: Current.user.webauthn_id, name: Current.user.email_address, display_name: Current.user.name },
      exclude: Current.user.passkeys.pluck(:external_id),
      authenticator_selection: { resident_key: "required", user_verification: "required" }
    )
    session[:passkey_registration_challenge] = { "challenge" => options.challenge, "issued_at" => Time.current.to_i }
    render json: options
  end
end
