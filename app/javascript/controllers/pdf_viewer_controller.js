import { Controller } from "@hotwired/stimulus"

// Drives PDF.js inside markup rendered by the server: the scroll container,
// toolbar controls and the thumbnail rail all come from the document partial.
export default class extends Controller {
  static targets = ["container", "pageNumber", "pageCount", "zoom", "scaleSelect", "findInput", "findStatus", "thumb", "status"]
  static values = { url: String, workerSrc: String }

  async connect() {
    this.keydown = this.keydown.bind(this)
    window.addEventListener("keydown", this.keydown)
    // Fit width and Fit page follow the stage when the details panel or the
    // side by side text opens or closes.
    this.resizeObserver = new ResizeObserver(() => this.refit())
    this.resizeObserver.observe(this.containerTarget)

    try {
      const pdfjsLib = await import("pdfjs-dist")
      globalThis.pdfjsLib = pdfjsLib
      const { EventBus, PDFLinkService, PDFFindController, PDFViewer } = await import("pdfjs-dist/web/pdf_viewer")
      pdfjsLib.GlobalWorkerOptions.workerSrc = this.workerSrcValue

      this.eventBus = new EventBus()
      this.linkService = new PDFLinkService({ eventBus: this.eventBus })
      this.findController = new PDFFindController({ eventBus: this.eventBus, linkService: this.linkService })
      this.viewer = new PDFViewer({
        container: this.containerTarget,
        eventBus: this.eventBus,
        linkService: this.linkService,
        findController: this.findController,
        removePageBorders: true
      })
      this.linkService.setViewer(this.viewer)

      this.eventBus.on("pagesinit", () => {
        this.viewer.currentScaleValue = this.initialScale()
        this.statusTarget.hidden = true
        // Links like /documents/1#page=3 open at that page.
        const page = parseInt(window.location.hash.match(/page=(\d+)/)?.[1], 10)
        if (page >= 1 && page <= this.pdf.numPages) this.viewer.currentPageNumber = page
      })
      this.eventBus.on("pagechanging", ({ pageNumber }) => this.pageChanged(pageNumber))
      this.eventBus.on("scalechanging", ({ scale, presetValue }) => this.scaleChanged(scale, presetValue))
      this.eventBus.on("updatefindmatchescount", ({ matchesCount }) => this.showMatches(matchesCount))
      this.eventBus.on("updatefindcontrolstate", ({ state, matchesCount }) => this.showMatches(matchesCount, state))

      // Scans often use JBIG2, CCITT fax or JPEG 2000 images, which PDF.js
      // decodes with the WebAssembly files in public/pdfjs; without them those
      // pages render blank.
      this.loadingTask = pdfjsLib.getDocument({
        url: this.urlValue,
        withCredentials: true,
        wasmUrl: "/pdfjs/wasm/",
        cMapUrl: "/pdfjs/cmaps/",
        cMapPacked: true,
        standardFontDataUrl: "/pdfjs/standard_fonts/",
        iccUrl: "/pdfjs/iccs/"
      })
      this.pdf = await this.loadingTask.promise
      this.viewer.setDocument(this.pdf)
      this.linkService.setDocument(this.pdf)
      this.pageCountTarget.textContent = this.pdf.numPages
    } catch (error) {
      console.error(error)
      this.statusTarget.hidden = false
      this.statusTarget.textContent = "This PDF could not be displayed. Download it to view it."
    }
  }

  disconnect() {
    window.removeEventListener("keydown", this.keydown)
    this.resizeObserver?.disconnect()
    this.loadingTask?.destroy()
    this.pdf = null
  }

  // Toolbar

  zoomIn() { this.viewer?.increaseScale() }
  zoomOut() { this.viewer?.decreaseScale() }

  setScale() {
    if (this.viewer) this.viewer.currentScaleValue = this.scaleSelectTarget.value
    this.rememberScale(this.scaleSelectTarget.value)
  }

  previousPage() { this.viewer?.previousPage() }
  nextPage() { this.viewer?.nextPage() }

  goToTypedPage(event) {
    const page = parseInt(this.pageNumberTarget.value, 10)
    if (this.pdf && page >= 1 && page <= this.pdf.numPages) this.viewer.currentPageNumber = page
    else this.pageNumberTarget.value = this.viewer?.currentPageNumber || 1
    event.preventDefault()
  }

  goTo({ params: { page } }) {
    if (this.viewer) this.viewer.currentPageNumber = page
  }

  // reading-mode:go-to from a page heading in the text.
  showPage({ detail: { page } }) {
    if (this.viewer) this.viewer.currentPageNumber = page
  }

  refit() {
    const preset = this.viewer?.currentScaleValue
    if (this.containerTarget.clientWidth && ["page-width", "page-fit", "auto"].includes(preset)) this.viewer.currentScaleValue = preset
  }

  fullscreen() {
    if (document.fullscreenElement) document.exitFullscreen()
    else this.element.requestFullscreen?.()
  }

  // Find

  find(event) {
    const again = event?.type === "keydown"
    this.dispatchFind(again ? "again" : "", event?.shiftKey)
    if (event?.type === "keydown") event.preventDefault()
  }

  findNext() { this.dispatchFind("again", false) }
  findPrevious() { this.dispatchFind("again", true) }

  dispatchFind(type, findPrevious = false) {
    if (!this.eventBus) return
    const query = this.findInputTarget.value
    if (!query) return this.findStatusTarget.textContent = ""
    this.eventBus.dispatch("find", {
      source: this, type, query, caseSensitive: false, entireWord: false, highlightAll: true, findPrevious, matchDiacritics: false
    })
  }

  showMatches(matchesCount, state) {
    if (!this.findInputTarget.value) return this.findStatusTarget.textContent = ""
    if (state === 1 || matchesCount?.total === 0) return this.findStatusTarget.textContent = "No matches"
    if (matchesCount?.total) this.findStatusTarget.textContent = `${matchesCount.current} of ${matchesCount.total}`
  }

  // Keyboard: j/k or arrows for pages, + and - to zoom, 0 to fit width,
  // / or Ctrl+F to find, f for fullscreen.
  keydown(event) {
    if (!this.viewer || !this.element.isConnected) return
    const typing = event.target.closest("input, textarea, select, [contenteditable]")
    // The find field is hidden when the viewer is narrow; the browser's own find takes over.
    const findShown = this.findInputTarget.offsetParent !== null
    if ((event.ctrlKey || event.metaKey) && event.key === "f" && findShown) {
      event.preventDefault()
      return this.findInputTarget.focus()
    }
    if (typing || event.ctrlKey || event.metaKey || event.altKey) return

    const actions = {
      j: () => this.nextPage(), ArrowRight: () => this.nextPage(), k: () => this.previousPage(), ArrowLeft: () => this.previousPage(),
      "+": () => this.zoomIn(), "=": () => this.zoomIn(), "-": () => this.zoomOut(),
      "0": () => { this.viewer.currentScaleValue = "page-width" }, "/": () => findShown && this.findInputTarget.focus(), f: () => this.fullscreen()
    }
    if (actions[event.key]) {
      event.preventDefault()
      actions[event.key]()
    }
  }

  // State

  pageChanged(pageNumber) {
    this.pageNumberTarget.value = pageNumber
    this.dispatch("page", { detail: { page: pageNumber } })
    this.thumbTargets.forEach((thumb) => {
      const current = Number(thumb.dataset.pdfViewerPageParam) === pageNumber
      thumb.toggleAttribute("aria-current", current)
      if (current) thumb.scrollIntoView({ block: "nearest" })
    })
  }

  scaleChanged(scale, presetValue) {
    this.zoomTarget.textContent = `${Math.round(scale * 100)}%`
    const preset = presetValue && this.scaleSelectTarget.querySelector(`el-option[value="${CSS.escape(presetValue)}"]`)
    this.scaleSelectTarget.value = preset ? presetValue : ""
  }

  initialScale() {
    try { return localStorage.getItem("pdf-viewer:scale") || "page-width" } catch { return "page-width" }
  }

  rememberScale(value) {
    try { localStorage.setItem("pdf-viewer:scale", value) } catch {}
  }
}
