import { Controller } from "@hotwired/stimulus"

// Locks AI-only settings while "Use AI" is off. Gated fields sit in
// fieldsets, so disabling them also keeps them out of the submitted form.
export default class extends Controller {
  static targets = ["toggle", "gated", "hint"]

  connect() {
    this.update()
  }

  update() {
    const on = this.toggleTarget.checked
    this.gatedTargets.forEach((fieldset) => {
      fieldset.disabled = !on
      fieldset.classList.toggle("opacity-50", !on)
    })
    this.hintTargets.forEach((hint) => (hint.hidden = on))
  }
}
