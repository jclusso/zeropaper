import { Controller } from "@hotwired/stimulus"

// Copies text to the clipboard and briefly confirms it.
export default class extends Controller {
  static targets = ["label"]
  static values = { text: String }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)
      this.flash("Copied")
    } catch {
      this.flash("Copy failed")
    }
  }

  flash(text) {
    if (!this.hasLabelTarget) return

    clearTimeout(this.timer)
    this.labelTarget.textContent = text
    this.timer = setTimeout(() => { this.labelTarget.textContent = "Copy" }, 1500)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
