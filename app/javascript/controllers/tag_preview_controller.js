import { Controller } from "@hotwired/stimulus"

// Shows the tag chip with the typed name and the chosen color.
export default class extends Controller {
  static targets = ["name", "chip"]

  update() {
    const chosen = this.element.querySelector("input[type=radio]:checked")
    this.chipTarget.textContent = this.nameTarget.value.trim() || "Tag name"
    if (chosen) this.chipTarget.className = chosen.dataset.chipClass
  }
}
