import { Controller } from "@hotwired/stimulus"

// Shows the key and address fields a provider kind needs, and labels each
// as required or optional.
export default class extends Controller {
  static targets = ["kind", "key", "keyRequirement", "baseUrl", "baseUrlRequirement", "customEndpoint"]
  static values = { requirements: Object }

  connect() {
    this.update()
  }

  update() {
    const spec = this.requirementsValue[this.kind] || {}
    const baseRequired = spec.base_url === "required"
    const baseFilled = this.baseUrlTarget.querySelector("input")?.value

    this.keyTarget.hidden = spec.key === "none"
    this.keyRequirementTarget.textContent = spec.key === "required" ? "" : "Optional"
    this.baseUrlTarget.hidden = !(baseRequired || baseFilled || this.showCustom)
    this.baseUrlRequirementTarget.textContent = baseRequired ? "" : "Optional. Leave blank for the provider's default."
    if (this.hasCustomEndpointTarget) this.customEndpointTarget.hidden = !this.baseUrlTarget.hidden
  }

  revealEndpoint() {
    this.showCustom = true
    this.update()
    this.baseUrlTarget.querySelector("input")?.focus()
  }

  get kind() {
    return this.kindTarget.value || this.kindTarget.getAttribute("value")
  }
}
