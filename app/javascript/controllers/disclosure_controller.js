import { Controller } from "@hotwired/stimulus"

// Expands and collapses a section, keeping it open for this tab's session
// (keyed, e.g. per document) so live refreshes and resolved items don't fold
// it away.
export default class extends Controller {
  static targets = ["content", "button"]
  static values = { key: String }

  connect() {
    this.restore = this.restore.bind(this)
    document.addEventListener("turbo:morph", this.restore)
    this.restore()
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this.restore)
  }

  toggle() {
    this.set(this.contentTarget.hidden)
  }

  restore() {
    try {
      if (sessionStorage.getItem(`disclosure:${this.keyValue}`) === "open") this.set(true, false)
    } catch {}
  }

  set(open, remember = true) {
    this.contentTarget.hidden = !open
    this.buttonTargets.forEach((button) => button.setAttribute("aria-expanded", open))
    if (!remember) return
    try {
      open ? sessionStorage.setItem(`disclosure:${this.keyValue}`, "open") : sessionStorage.removeItem(`disclosure:${this.keyValue}`)
    } catch {}
  }
}
