import { Controller } from "@hotwired/stimulus"

// Refreshes the page while background work it shows is still running.
export default class extends Controller {
  static values = { interval: { type: Number, default: 3000 } }

  connect() {
    this.timer = setTimeout(() => Turbo.visit(window.location.href, { action: "replace" }), this.intervalValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
