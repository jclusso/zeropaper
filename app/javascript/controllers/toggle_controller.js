import { Controller } from "@hotwired/stimulus"

// Shows and hides content that is already on the page, remembering the state
// per key so a collapsed panel stays collapsed between documents and through
// live page refreshes.
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

  restore() {
    if (!this.hasKeyValue) return
    try {
      const stored = localStorage.getItem(`toggle:${this.keyValue}`)
      if (stored !== null) this.set(stored === "open")
    } catch {}
  }

  toggle() {
    this.set(this.contentTargets[0].hidden)
  }

  show() {
    this.set(true)
  }

  set(open) {
    this.contentTargets.forEach((target) => (target.hidden = !open))
    this.buttonTargets.forEach((button) => button.setAttribute("aria-expanded", open))
    if (this.hasKeyValue) {
      try { localStorage.setItem(`toggle:${this.keyValue}`, open ? "open" : "closed") } catch {}
    }
  }
}
