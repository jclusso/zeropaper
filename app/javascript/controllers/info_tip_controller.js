import { Controller } from "@hotwired/stimulus"

// Opens an info tip's popover on hover and pins it open on click, tap or
// Enter, so a click that follows a hover keeps the tip instead of closing it.
// Escape or clicking elsewhere closes it (light dismiss).
export default class extends Controller {
  static targets = ["popover"]

  connect() {
    this.closed = (event) => { if (event.newState === "closed") this.pinned = false }
    this.popoverTarget.addEventListener("toggle", this.closed)
  }

  disconnect() {
    clearTimeout(this.closing)
    this.popoverTarget.removeEventListener("toggle", this.closed)
  }

  show() {
    clearTimeout(this.closing)
    if (this.open) return
    this.popoverTarget.showPopover()
    this.hoverOpenedAt = Date.now()
  }

  hide() {
    if (this.pinned) return
    this.closing = setTimeout(() => { if (this.open && !this.pinned) this.popoverTarget.hidePopover() }, 150)
  }

  toggle(event) {
    event.preventDefault()
    clearTimeout(this.closing)
    const justHovered = Date.now() - (this.hoverOpenedAt || 0) < 800

    if (this.open && !justHovered && this.pinned) {
      this.popoverTarget.hidePopover()
    } else {
      if (!this.open) this.popoverTarget.showPopover()
      this.pinned = true
    }
  }

  get open() {
    return this.popoverTarget.matches(":popover-open")
  }
}
