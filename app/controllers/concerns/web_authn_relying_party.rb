module WebAuthnRelyingParty
  extend ActiveSupport::Concern

  private
    def relying_party
      @relying_party ||= WebAuthn::RelyingParty.new(id: request.host, name: "ZeroPaper", allowed_origins: [ request.base_url ])
    end

    # The fields of a PublicKeyCredential's toJSON() for registration and sign-in.
    def credential_params
      params.require(:credential).permit(
        :id, :rawId, :type, :authenticatorAttachment,
        response: [ :clientDataJSON, :attestationObject, :authenticatorData, :signature, :userHandle, :publicKey, :publicKeyAlgorithm, { transports: [] } ],
        clientExtensionResults: {}
      ).to_h
    end
end
