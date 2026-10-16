import { Controller } from "@hotwired/stimulus"

// Submits the form when a filter changes.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
