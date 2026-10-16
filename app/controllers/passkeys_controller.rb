class PasskeysController < ApplicationController
  include WebAuthnRelyingParty

  def create
    challenge = session.delete(:passkey_registration_challenge)
    return render(json: { error: "Start again." }, status: :unprocessable_entity) unless challenge

    Passkey.register(user: Current.user, credential: credential_params,
      challenge: challenge, relying_party: relying_party, name: params[:name])
    flash[:notice] = "Passkey added."
    render json: { location: profile_path }
  rescue WebAuthn::Error, ActiveRecord::RecordInvalid => error
    render json: { error: "Could not add the passkey (#{error.message})." }, status: :unprocessable_entity
  end

  def destroy
    Current.user.passkeys.find(params[:id]).destroy
    redirect_to profile_path, notice: "Passkey removed."
  end
end
