import { Controller } from "@hotwired/stimulus"

// Shows content while a choice matches, e.g. the provider form only after
// choosing to use AI, or the Docling URL only when Docling is chosen. The
// choice is the `source` field's value when there is one ("true" or "false"
// for a checkbox), otherwise the checked radio. Fields in hidden content are
// disabled, so they stay out of the submitted form.
export default class extends Controller {
  static targets = ["content", "source"]
  static values = { when: String }

  connect() {
    this.update()
  }

  update() {
    const chosen = !this.hasSourceTarget
      ? this.element.querySelector("input[type=radio]:checked")?.value
      : this.sourceTarget.type === "checkbox"
        ? String(this.sourceTarget.checked)
        : this.sourceTarget.value

    this.contentTargets.forEach((content) => {
      content.hidden = chosen !== this.whenValue
      if (content instanceof HTMLFieldSetElement) {
        content.disabled = content.hidden
      } else {
        content.querySelectorAll("input, select, textarea").forEach((field) => (field.disabled = content.hidden))
        content.querySelectorAll("el-select").forEach((select) => select.toggleAttribute("disabled", content.hidden))
      }
    })
  }
}
