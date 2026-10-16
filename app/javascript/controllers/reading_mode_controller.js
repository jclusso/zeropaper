import { Controller } from "@hotwired/stimulus"

// Switches the document view between the pages, the extracted text, or both
// side by side. Side by side keeps the text on the page the viewer shows.
export default class extends Controller {
  static targets = ["button", "reader", "page"]

  connect() {
    this.reapply = () => this.apply(this.mode)
    document.addEventListener("turbo:morph", this.reapply)
    this.apply(this.stored() || "pages")
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this.reapply)
  }

  select({ params: { mode } }) {
    this.apply(mode)
    try { localStorage.setItem("document:view", mode) } catch {}
  }

  apply(mode) {
    this.mode = mode
    this.element.dataset.view = mode
    this.buttonTargets.forEach((button) => button.setAttribute("aria-pressed", button.dataset.readingModeModeParam === mode))
  }

  // pdf-viewer:page events from the viewer.
  follow({ detail: { page } }) {
    if (this.mode !== "side" || !this.hasReaderTarget) return
    const section = this.pageTargets[page - 1]
    if (section) this.readerTarget.scrollTo({ top: section.offsetTop - 16, behavior: "smooth" })
  }

  showPage({ params: { page } }) {
    if (this.mode === "text") this.select({ params: { mode: "side" } })
    this.dispatch("go-to", { detail: { page }, prefix: "reading-mode" })
  }

  stored() {
    try { return localStorage.getItem("document:view") } catch { return null }
  }
}
