import { Controller } from "@hotwired/stimulus"

// Links the PDF viewers in the side by side comparison: scrolling, paging or
// zooming one moves the others the same way. Linking again after moving them
// apart brings the others back to the one moved last. Pages follow the
// server's pairing, read from the viewers' frame (the pages target), so a
// page only one document has is scrolled past while the other waits at its
// next page.
export default class extends Controller {
  static targets = ["link", "pages", "blank", "frame"]
  static outlets = ["pdf-viewer"]
  static values = { linked: { type: Boolean, default: true } }

  pdfViewerOutletConnected(viewer) { viewer.compare = this }
  pdfViewerOutletDisconnected(viewer) { viewer.compare = null }

  toggle() { this.linkedValue = !this.linkedValue }

  // Reloads the viewers with or without blank and removed pages.
  toggleBlank() {
    const shown = this.blankTarget.getAttribute("aria-pressed") !== "true"
    this.blankTarget.setAttribute("aria-pressed", shown)
    const url = new URL(this.frameTarget.src, window.location.href)
    if (shown) url.searchParams.set("blank", "show")
    else url.searchParams.delete("blank")
    this.frameTarget.src = url.toString()
  }

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
    this.followers(source).forEach((viewer) => viewer.scrollToPosition(this.pairedPosition(source, viewer, position)))
  }

  // Rows map document ids to 1-based page numbers in each viewer, leaving
  // out a document with no page in that row.
  pairedPosition(source, viewer, position) {
    const rows = this.rows()
    const from = this.documentId(source), to = this.documentId(viewer)
    const index = rows.findIndex((row) => row[from] === position.page + 1)
    if (index < 0) return position

    const row = rows.slice(index).find((row) => row[to])
    if (!row) return { ...position, page: viewer.viewer.pagesCount - 1, offset: 1 }
    return { ...position, page: row[to] - 1, offset: row === rows[index] ? position.offset : 0 }
  }

  rows() {
    return this.hasPagesTarget && this.pagesTarget.dataset.pages ? JSON.parse(this.pagesTarget.dataset.pages) : []
  }

  documentId(viewer) {
    return viewer.element.closest("[data-comparison-viewer]")?.dataset.comparisonViewer
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
