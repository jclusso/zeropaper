import { Controller } from "@hotwired/stimulus"

// Switches between panels. The server picks the first tab; a tab someone
// chose stays chosen through live page refreshes for as long as it exists.
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    this.reapply = this.reapply.bind(this)
    document.addEventListener("turbo:morph", this.reapply)
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this.reapply)
  }

  select({ params: { name } }) {
    this.current = name
    this.show(name)
  }

  reapply() {
    if (this.current && this.tabTargets.some((tab) => tab.dataset.tabsNameParam === this.current)) this.show(this.current)
  }

  show(name) {
    this.tabTargets.forEach((tab) => tab.setAttribute("aria-selected", tab.dataset.tabsNameParam === name))
    this.panelTargets.forEach((panel) => (panel.hidden = panel.dataset.name !== name))
  }
}
