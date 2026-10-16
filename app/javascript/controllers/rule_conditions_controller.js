import { Controller } from "@hotwired/stimulus"

// Adds and removes rule condition rows from the <template>, and switches a
// row between text comparisons and a source choice when its field changes.
export default class extends Controller {
  static targets = ["list", "row", "template"]

  add() {
    const html = this.templateTarget.innerHTML.replaceAll("__INDEX__", `${Date.now()}`)
    this.listTarget.insertAdjacentHTML("beforeend", html)
    this.rowTargets.at(-1).querySelector("input[type=text]")?.focus()
  }

  remove(event) {
    if (this.rowTargets.length <= 1) return
    event.target.closest("[data-rule-conditions-target=row]").remove()
  }

  fieldChanged(event) {
    const row = event.target.closest("[data-rule-conditions-target=row]")
    const source = event.target.value === "source"

    this.toggle(row, "text-operator", !source)
    this.toggle(row, "source-operator", source)
    this.toggle(row, "text-value", !source)
    this.toggle(row, "source-value", source)
  }

  // Hidden parts are disabled so they stay out of the submitted form;
  // el-select is a form field itself and takes the disabled attribute.
  toggle(row, role, on) {
    const part = row.querySelector(`[data-role=${role}]`)
    part.hidden = !on
    part.querySelectorAll("input, button").forEach((field) => (field.disabled = !on))
    part.querySelectorAll("el-select").forEach((select) => select.toggleAttribute("disabled", !on))
  }
}
