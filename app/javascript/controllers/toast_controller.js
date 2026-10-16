import { Controller } from "@hotwired/stimulus"

// A flash message shown as a floating toast. On connect it moves into the
// persistent #toasts stack, so page refreshes and Turbo Stream updates don't
// cut it short, then dismisses itself after its delay.
export default class extends Controller {
  static values = { delay: { type: Number, default: 4000 } }

  connect() {
    this.place()
  }

  // The stack is carried over from the previous page (data-turbo-permanent),
  // and when the layout changes it is swapped in after this toast connects.
  // Wait a frame and try again until it is there.
  place(attempt = 0) {
    const stack = document.getElementById("toasts")
    if (stack && this.element.parentElement === stack) {
      requestAnimationFrame(() => this.element.removeAttribute("data-closed"))
      this.timer = setTimeout(() => this.dismiss(), this.delayValue)
    } else if (stack && stack.isConnected) {
      stack.append(this.element)
    } else if (attempt < 30) {
      requestAnimationFrame(() => this.place(attempt + 1))
    }
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  pause() {
    clearTimeout(this.timer)
  }

  resume() {
    this.timer = setTimeout(() => this.dismiss(), 1500)
  }

  dismiss() {
    clearTimeout(this.timer)
    this.element.setAttribute("data-closed", "")
    setTimeout(() => this.element.remove(), 200)
  }
}
