import { Controller } from "@hotwired/stimulus"

// Zoom for scans and photos shown without a PDF rendition.
export default class extends Controller {
  static targets = ["image", "zoom"]

  connect() {
    this.scale = 1
    this.render()
  }

  zoomIn() { this.setScale(this.scale * 1.25) }
  zoomOut() { this.setScale(this.scale / 1.25) }
  fit() { this.setScale(1) }

  setScale(scale) {
    this.scale = Math.min(6, Math.max(0.25, scale))
    this.render()
  }

  render() {
    this.imageTarget.style.width = `${this.scale * 100}%`
    if (this.hasZoomTarget) this.zoomTarget.textContent = `${Math.round(this.scale * 100)}%`
  }
}
