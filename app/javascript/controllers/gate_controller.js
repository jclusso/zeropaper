import { Controller } from "@hotwired/stimulus"

// Locks settings while the switch that enables them is off, such as the AI
// settings under "Use AI" or the backup schedule under "Back up
// automatically". Gated fields sit in fieldsets, so disabling them also keeps
// them out of the submitted form and the saved values stay as they were.
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
