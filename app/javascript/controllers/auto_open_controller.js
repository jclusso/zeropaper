import { Controller } from "@hotwired/stimulus"

// Clicks its element once on page load, e.g. to open a dialog requested by a
// link like ?review=pages.
export default class extends Controller {
  connect() {
    requestAnimationFrame(() => this.element.click())
  }
}
