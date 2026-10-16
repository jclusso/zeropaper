import { Controller } from "@hotwired/stimulus"

// Follows the operating system's light or dark mode while the user's theme
// is "system". The theme itself is a profile setting rendered by the server.
export default class extends Controller {
  connect() {
    this.media = window.matchMedia("(prefers-color-scheme: dark)")
    this.mediaChanged = () => this.apply()
    this.media.addEventListener("change", this.mediaChanged)
    this.apply()
  }

  disconnect() {
    this.media.removeEventListener("change", this.mediaChanged)
  }

  apply() {
    const theme = this.element.dataset.theme
    this.element.classList.toggle("dark", theme === "dark" || (theme === "system" && this.media.matches))
  }
}
