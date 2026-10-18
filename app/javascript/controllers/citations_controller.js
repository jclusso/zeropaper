import { Controller } from "@hotwired/stimulus"

// Shows a cited document's card under its numbered marker on hover or
// focus, and keeps it open while the pointer moves onto the card. Markers
// come from rendered Markdown, so a card is found by the link it shares.
export default class extends Controller {
  static targets = ["card"]

  disconnect() {
    clearTimeout(this.opening)
    clearTimeout(this.closing)
    this.close()
  }

  show(event) {
    if (event.target.closest("[popover]")) return clearTimeout(this.closing)

    const marker = event.target.closest("a.citation-marker")
    const card = marker && this.cardTargets.find((card) => card.dataset.href === marker.getAttribute("href"))
    if (!card) return

    clearTimeout(this.closing)
    clearTimeout(this.opening)
    // Hovering opens after a moment, so passing over a marker does not flash its card.
    this.opening = setTimeout(() => this.open(card, marker), event.type === "focusin" ? 0 : 200)
  }

  hide(event) {
    if (!event.target.closest("a.citation-marker, [popover]")) return
    if (event.relatedTarget && this.current?.contains(event.relatedTarget)) return

    clearTimeout(this.opening)
    this.closing = setTimeout(() => this.close(), 150)
  }

  open(card, marker) {
    if (this.current !== card) this.close()
    marker.setAttribute("aria-describedby", card.id)
    if (!card.matches(":popover-open")) card.showPopover()
    this.current = card
    this.place(card, marker)
  }

  close() {
    if (this.current?.matches(":popover-open")) this.current.hidePopover()
    this.current = null
  }

  // Below the marker, or above it when there is no room, kept inside the window.
  place(card, marker) {
    const anchor = marker.getBoundingClientRect()
    const gap = 6
    const left = Math.max(8, Math.min(anchor.left, window.innerWidth - card.offsetWidth - 8))
    const below = anchor.bottom + gap
    const top = below + card.offsetHeight > window.innerHeight - 8 ? anchor.top - gap - card.offsetHeight : below

    Object.assign(card.style, { position: "fixed", inset: "auto", left: `${left}px`, top: `${Math.max(8, top)}px` })
  }
}
