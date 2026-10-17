import { Controller } from "@hotwired/stimulus"

// Keeps the page editor's submit button in step with the selected pages.
// With nothing selected but blank pages suggested, the button keeps them
// instead, which marks them not blank.
export default class extends Controller {
  static targets = ["page", "submit", "label", "removeIcon", "keepIcon"]
  static values = { suggested: Number }

  connect() {
    this.update()
  }

  update() {
    const count = this.pageTargets.filter((page) => page.checked).length
    const total = this.pageTargets.length
    const keeping = count === 0 && this.suggestedValue > 0

    if (keeping) {
      this.labelTarget.textContent = `Keep ${this.suggestedValue === 1 ? "page" : `${this.suggestedValue} pages`}`
    } else {
      this.labelTarget.textContent = count === 0 ? "Remove pages" : `Remove ${count} ${count === 1 ? "page" : "pages"}`
    }
    this.submitTarget.className = `${keeping ? "btn-primary" : "btn-danger-solid"} btn-sm`
    this.removeIconTarget.hidden = keeping
    this.keepIconTarget.hidden = !keeping
    this.submitTarget.disabled = (count === 0 && !keeping) || count >= total
    this.submitTarget.title = count >= total ? "A document needs at least one page." : ""
  }

  // An edit that went through refreshes the document behind the dialog,
  // which a refresh leaves open, so it closes to show the result.
  close({ detail: { success } }) {
    if (success) this.element.closest("dialog")?.close()
  }
}
