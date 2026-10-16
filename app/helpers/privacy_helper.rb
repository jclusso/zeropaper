module PrivacyHelper
  EXPLANATION = "Never sent to an AI provider. Read on this machine with local OCR and rules, and left out of anything Research sends to AI.".freeze

  # The standard Private badge. Hover or focus shows what private means and,
  # for a document, why it is private. Pass interactive: false inside links.
  def private_badge(label: "Private", reason: nil, interactive: true)
    render "shared/private_badge", label: label, reason: reason, interactive: interactive, tooltip_id: "private-tip-#{SecureRandom.hex(4)}"
  end

  # What making a document not private will do, for the confirm dialog.
  def publicize_confirmation(document)
    providers = document_exposure(document).values.uniq
    if providers.any?
      "It will be processed again, and its file and text will be sent to the AI providers in Settings: #{providers.to_sentence}."
    else
      "AI is off, so it stays on this machine for now. Once AI is turned on, its file and text will be sent to the AI providers in Settings."
    end
  end
end
