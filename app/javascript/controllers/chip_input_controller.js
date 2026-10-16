import { Controller } from "@hotwired/stimulus"

// A box of chips over a Tailwind Plus el-autocomplete. Enter, Tab or a comma
// adds the highlighted suggestion or the typed name; Backspace in an empty box
// removes the last chip. Chosen values leave the suggestion list and return to
// it when removed. A change event fires when focus leaves after the chips
// changed, so a filter form submits once rather than on every chip.
export default class extends Controller {
  static targets = ["chips", "token", "input", "list", "option", "stash", "template"]
  static values = { creatable: Boolean }

  connect() {
    this.tokenTargets.forEach((token) => this.stashOption(token.dataset.value))
    this.leave = this.leave.bind(this)
    this.element.addEventListener("focusout", this.leave)
  }

  disconnect() {
    this.element.removeEventListener("focusout", this.leave)
  }

  leave(event) {
    if (!this.changed || this.element.contains(event.relatedTarget)) return
    this.changed = false
    this.dispatch("change")
  }

  focus(event) {
    if (event.target === event.currentTarget || event.target === this.chipsTarget) this.inputTarget.focus()
  }

  keydown(event) {
    const text = this.inputTarget.value.trim()
    const active = this.activeOption()

    switch (event.key) {
      case "Enter":
        if (active) return // el-autocomplete picks it and fires change
        if (text) {
          event.preventDefault()
          this.add(text)
        }
        break
      case ",":
        event.preventDefault()
        if (active || text) this.add(active?.dataset.label || text)
        break
      case "Tab":
        if (active || text) {
          event.preventDefault()
          this.add(active?.dataset.label || text)
        }
        break
      case "Backspace":
        if (!this.inputTarget.value && this.tokenTargets.length) this.removeToken(this.tokenTargets.at(-1))
        break
    }
  }

  chosen() {
    const text = this.inputTarget.value.trim()
    if (text) this.add(text)
  }

  remove(event) {
    event.stopPropagation()
    this.removeToken(event.target.closest("[data-chip-input-target=token]"))
    this.inputTarget.focus()
  }

  // private

  add(text) {
    const option = this.findOption(text)
    const label = option?.dataset.label || text
    const value = option?.dataset.value || (this.creatableValue ? text : null)
    this.inputTarget.value = ""
    if (!value || this.tokenTargets.some((token) => token.dataset.label.toLowerCase() === label.toLowerCase())) return

    const token = this.templateTarget.content.firstElementChild.cloneNode(true)
    token.dataset.value = value
    token.dataset.label = label
    if (option?.dataset.chipClass) token.className = option.dataset.chipClass
    token.querySelector("[data-role=label]").textContent = label
    token.querySelector("[data-role=value]").value = value
    this.chipsTarget.append(token)
    this.stashOption(value)
    this.changed = true
    if (this.listTarget.matches(":popover-open")) this.listTarget.hidePopover()
  }

  removeToken(token) {
    if (!token) return
    const option = this.stashTarget.querySelector(`[data-value="${CSS.escape(token.dataset.value)}"]`)
    if (option) this.listTarget.append(option)
    token.remove()
    this.changed = true
  }

  stashOption(value) {
    const option = this.optionTargets.find((candidate) => candidate.dataset.value === value)
    if (option && option.parentElement !== this.stashTarget) this.stashTarget.append(option)
  }

  findOption(text) {
    const wanted = text.toLowerCase()
    return this.optionTargets.find((option) => option.dataset.label.toLowerCase() === wanted)
  }

  activeOption() {
    const id = this.inputTarget.getAttribute("aria-activedescendant")
    return id ? document.getElementById(id) : null
  }
}
