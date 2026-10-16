module PrivacyHelper
  EXPLANATION = "Never sent to an AI provider. Read on this machine with local OCR and rules, stored encrypted, and left out of anything Research sends to AI.".freeze

  # The standard Private badge. Hover or focus shows what private means and,
  # for a document, why it is private. Pass interactive: false inside links.
  def private_badge(label: "Private", reason: nil, interactive: true)
    render "shared/private_badge", label: label, reason: reason, interactive: interactive, tooltip_id: "private-tip-#{SecureRandom.hex(4)}"
  end
end
