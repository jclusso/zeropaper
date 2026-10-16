import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "backdrop"]

  open() {
    this.panelTarget.classList.remove("-translate-x-full")
    this.backdropTarget.hidden = false
  }

  close() {
    this.panelTarget.classList.add("-translate-x-full")
    this.backdropTarget.hidden = true
  }
}
