import { Controller } from "@hotwired/stimulus"

// Keeps a Tailwind Plus el-autocomplete in step with a hidden input: the text
// box shows the chosen option's label and the hidden input carries its value.
// Opening shows every option with the current one in view; the list only
// filters once something new is typed (the label shown is not a query).
// Marks the chosen option, offers "Create" for a new name when creatable,
// shows "No matches", and puts back the last choice when typed text matches
// nothing and new names are not allowed.
export default class extends Controller {
  static targets = ["input", "value", "list", "option", "create", "createLabel", "stash", "clear", "empty"]
  static values = { creatable: Boolean }

  connect() {
    this.filterAllUntilTyped()
    // Capture runs before el-autocomplete's own input handler filters.
    this.typing = (event) => { if (event.isTrusted && event.target === this.inputTarget) this.dirty = true }
    this.opened = (event) => {
      if (event.newState !== "open") return
      this.optionTargets.find((option) => option.hasAttribute("data-selected"))?.scrollIntoView({ block: "nearest" })
      // Opening re-filters and moves the caret; keep the label selected so
      // typing replaces it.
      if (!this.dirty && document.activeElement === this.inputTarget) requestAnimationFrame(() => this.inputTarget.select())
    }
    this.element.addEventListener("input", this.typing, true)
    this.listTarget.addEventListener("toggle", this.opened)
  }

  disconnect() {
    this.element.removeEventListener("input", this.typing, true)
    this.listTarget.removeEventListener("toggle", this.opened)
  }

  // Select the label on focus so typing replaces it. A click places the
  // caret after focus, so the click that focused the box selects again.
  focused() {
    this.inputTarget.select()
    this.justFocused = true
  }

  clicked() {
    if (!this.justFocused) return
    this.justFocused = false
    this.inputTarget.select()
  }

  blurred() {
    this.justFocused = false
    this.dirty = false
  }

  typed(event) {
    // el-autocomplete fires a synthetic input when an option is chosen; only
    // real typing should filter, offer Create and reopen the list.
    if (!event.isTrusted) return

    const text = this.inputTarget.value.trim()
    if (this.hasCreateTarget) {
      this.createLabelTarget.textContent = text
      this.createTarget.setAttribute("value", text)
    }
    // Settle after el-autocomplete has filtered for this keystroke.
    requestAnimationFrame(() => this.settle(text))
  }

  keydown(event) {
    if (event.key === "Enter" && !this.inputTarget.getAttribute("aria-activedescendant")) this.commit()
    if (event.key === "Escape") this.inputTarget.value = this.chosenLabel()
  }

  commit() {
    this.dirty = false
    const text = this.inputTarget.value.trim()
    const option = this.find(text)

    if (option) {
      this.inputTarget.value = option.dataset.label
      this.choose(option.dataset.value)
    } else if (!text) {
      this.choose("")
    } else if (this.creatableValue) {
      this.inputTarget.value = text
      this.choose(text)
    } else {
      this.inputTarget.value = this.chosenLabel()
    }
    this.emptyTarget.hidden = true
  }

  clear() {
    this.inputTarget.value = ""
    this.choose("")
    this.inputTarget.focus()
  }

  // private

  // el-autocomplete filters by whatever the text box holds, and runs that
  // filter several times while opening. The label of the current choice is
  // not a query, so until the person types, its filter sees an empty query:
  // every option shows and arrow keys reach them all.
  filterAllUntilTyped() {
    const autocomplete = this.inputTarget.closest("el-autocomplete")
    const filter = autocomplete.filterOptions?.bind(autocomplete)
    if (!filter || autocomplete.filterOptions.wrapped) return

    autocomplete.filterOptions = () => {
      if (this.dirty) return filter()
      const input = this.inputTarget
      const { value, selectionStart, selectionEnd, selectionDirection } = input
      input.value = ""
      try {
        filter()
      } finally {
        // Assigning the value moves the caret; put the selection back.
        input.value = value
        if (selectionStart !== null) input.setSelectionRange(selectionStart, selectionEnd, selectionDirection)
      }
    }
    autocomplete.filterOptions.wrapped = true
  }

  settle(text) {
    const offer = this.hasCreateTarget && text !== "" && !this.find(text)
    if (this.hasCreateTarget) {
      // Only in the list while offered; elsewhere el-autocomplete's filter
      // would show it again whenever its text contains the query.
      const home = offer ? this.listTarget : this.stashTarget
      if (this.createTarget.parentElement !== home) home.append(this.createTarget)
    }

    const visible = this.optionTargets.some((option) => !option.hidden) || offer
    this.emptyTarget.hidden = visible || text === ""
    if (visible && document.activeElement === this.inputTarget && !this.listTarget.matches(":popover-open")) {
      this.listTarget.showPopover()
    }
  }

  choose(value) {
    if (this.hasClearTarget) this.clearTarget.hidden = value === "" || this.inputTarget.disabled
    this.optionTargets.forEach((option) => option.toggleAttribute("data-selected", value !== "" && option.dataset.value === value))
    if (this.valueTarget.value === value) return

    this.valueTarget.value = value
    this.valueTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  find(text) {
    const wanted = text.toLowerCase()
    if (!wanted) return null
    return this.optionTargets.find((option) => option.dataset.label.toLowerCase() === wanted)
  }

  chosenLabel() {
    const option = this.optionTargets.find((option) => option.dataset.value === this.valueTarget.value)
    if (option) return option.dataset.label
    return this.creatableValue ? this.valueTarget.value : ""
  }
}
