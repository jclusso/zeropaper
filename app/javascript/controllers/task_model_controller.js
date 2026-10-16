import { Controller } from "@hotwired/stimulus"

// When a task's provider changes, reloads the model picker with that
// provider's models. Choosing no provider clears and hides the picker.
export default class extends Controller {
  static targets = ["provider", "frame", "none"]
  static values = { url: String }

  providerChanged() {
    const id = this.providerTarget.value
    this.frameTarget.hidden = !id
    if (this.hasNoneTarget) this.noneTarget.hidden = !!id
    if (!id) {
      this.frameTarget.querySelectorAll("input").forEach((input) => (input.value = ""))
      return
    }
    this.frameTarget.src = this.urlValue.replace("__PROVIDER__", id)
  }
}
