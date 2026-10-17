import { Controller } from "@hotwired/stimulus"

// Links the PDF viewers in the side by side comparison: scrolling, paging or
// zooming one moves the others the same way. Linking again after moving them
// apart brings the others back to the one moved last.
export default class extends Controller {
  static targets = ["link"]
  static outlets = ["pdf-viewer"]
  static values = { linked: { type: Boolean, default: true } }

  pdfViewerOutletConnected(viewer) { viewer.compare = this }
  pdfViewerOutletDisconnected(viewer) { viewer.compare = null }

  toggle() { this.linkedValue = !this.linkedValue }

  linkedValueChanged(linked, wasLinked) {
    this.linkTargets.forEach((button) => button.setAttribute("aria-pressed", linked))
    if (linked && wasLinked === false) this.match(this.lastUsedViewer())
  }

  follow(source, name, value) {
    this.lastUsed = source
    this.followers(source).forEach((viewer) => viewer[name](value))
  }

  scrolled(source) {
    if (this.matching) return
    this.lastUsed = source
    this.scrollFollowers(source, source.scrollPosition())
  }

  // Keys go to the viewer holding focus, or else the one last moved.
  keyViewer() {
    return this.pdfViewerOutlets.find((viewer) => viewer.element.contains(document.activeElement)) ?? this.lastUsedViewer()
  }

  // private

  lastUsedViewer() {
    return this.pdfViewerOutlets.includes(this.lastUsed) ? this.lastUsed : this.pdfViewerOutlets[0]
  }

  followers(source) {
    if (!this.linkedValue) return []
    return this.pdfViewerOutlets.filter((viewer) => viewer !== source && viewer.viewer?.pagesCount)
  }

  scrollFollowers(source, position) {
    this.followers(source).forEach((viewer) => viewer.scrollToPosition(position))
  }

  // The followers' new zoom scrolls them, and those scrolls must not move
  // the source, so they are ignored until the next frame lines them up.
  match(source) {
    if (!source?.viewer?.pagesCount) return
    const position = source.scrollPosition()
    this.matching = true
    this.follow(source, "applyScale", source.viewer.currentScaleValue)
    requestAnimationFrame(() => {
      this.scrollFollowers(source, position)
      this.matching = false
    })
  }
}
