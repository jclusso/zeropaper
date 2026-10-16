import { Controller } from "@hotwired/stimulus"

// Checkbox menu behind a field-sized button. The button sums up the choice;
// a change event fires when the menu closes after the choice changed.
export default class extends Controller {
  static targets = ["summary", "menu", "search", "option", "checkbox", "empty", "footer"]
  static values = { placeholder: String }

  connect() {
    this.render()
  }

  changed() {
    this.dirty = true
    this.render()
  }

  clear() {
    this.checkboxTargets.forEach((box) => { box.checked = false })
    this.changed()
    this.close()
  }

  // Enter in the search box toggles the first match instead of submitting the form.
  pickFirst(event) {
    event.preventDefault()
    const option = this.optionTargets.find((candidate) => !candidate.hidden)
    if (!option) return
    const box = option.querySelector("input[type=checkbox]")
    box.checked = !box.checked
    this.changed()
  }

  close() {
    this.menuTarget.hidePopover()
  }

  filter() {
    const query = this.searchTarget.value.trim().toLowerCase()
    let shown = 0
    this.optionTargets.forEach((option) => {
      const match = option.dataset.label.toLowerCase().includes(query)
      option.hidden = !match
      if (match) shown++
    })
    this.emptyTarget.hidden = shown > 0
  }

  toggled(event) {
    if (event.newState === "open") {
      if (this.hasSearchTarget) this.searchTarget.focus()
      return
    }
    if (this.hasSearchTarget && this.searchTarget.value) {
      this.searchTarget.value = ""
      this.filter()
    }
    if (this.dirty) {
      this.dirty = false
      this.dispatch("change")
    }
  }

  render() {
    const labels = this.checkboxTargets.filter((box) => box.checked).map((box) => box.closest("label").dataset.label)
    this.summaryTarget.textContent = labels.length ? labels[0] + (labels.length > 1 ? ` +${labels.length - 1}` : "") : this.placeholderValue
    this.summaryTarget.classList.toggle("muted", labels.length === 0)
    this.summaryTarget.title = labels.join(", ")
    this.footerTarget.hidden = labels.length === 0
  }
}
