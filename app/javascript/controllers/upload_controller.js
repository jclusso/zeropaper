import { Controller } from "@hotwired/stimulus"

// Queues files chosen, dropped (folders included) or picked as a folder, then
// uploads them one file per request with per-file and overall progress.
// Rows come from the <template> in the page; this controller only fills them.
export default class extends Controller {
  static targets = ["form", "zone", "input", "folderInput", "private", "queue", "summary", "clear", "submit", "submitLabel",
    "overall", "overallBar", "list", "done", "doneSummary", "template"]
  static values = { url: String, concurrency: { type: Number, default: 3 } }

  connect() {
    this.items = []
    this.uploading = false
  }

  // Choosing

  // The drop zone is a label for the file picker, so the folder link has to
  // keep the click from also opening that.
  chooseFolder(event) {
    event.preventDefault()
    event.stopPropagation()
    this.folderInputTarget.click()
  }

  choose(event) {
    this.add(Array.from(event.target.files))
    event.target.value = ""
  }

  over(event) {
    event.preventDefault()
    this.zoneTarget.classList.add("border-strong-accent", "bg-strong-accent/[0.04]")
  }

  leave() {
    this.zoneTarget.classList.remove("border-strong-accent", "bg-strong-accent/[0.04]")
  }

  async drop(event) {
    event.preventDefault()
    this.leave()
    const entries = Array.from(event.dataTransfer.items || [])
      .map((item) => item.webkitGetAsEntry?.())
      .filter(Boolean)
    const files = entries.length ? (await Promise.all(entries.map((entry) => this.walk(entry)))).flat() : Array.from(event.dataTransfer.files)
    this.add(files)
  }

  // Reads a dropped file or, for a folder, every file inside it.
  async walk(entry) {
    if (entry.isFile) return new Promise((resolve) => entry.file((file) => resolve([ file ]), () => resolve([])))
    if (!entry.isDirectory) return []

    const reader = entry.createReader()
    const children = []
    let batch
    do {
      batch = await new Promise((resolve) => reader.readEntries(resolve, () => resolve([])))
      children.push(...batch)
    } while (batch.length > 0)
    return (await Promise.all(children.map((child) => this.walk(child)))).flat()
  }

  add(files) {
    if (this.uploading) return

    files.filter((file) => !file.name.startsWith(".")).forEach((file) => {
      const row = this.templateTarget.content.firstElementChild.cloneNode(true)
      const item = { file, row, state: "queued" }
      this.field(row, "name").textContent = file.webkitRelativePath || file.name
      this.field(row, "size").textContent = this.format(file.size)
      this.field(row, "remove").addEventListener("click", () => this.remove(item))
      this.listTarget.append(row)
      this.items.push(item)
    })
    this.render()
  }

  remove(item) {
    if (this.uploading) return
    item.row.remove()
    this.items = this.items.filter((other) => other !== item)
    this.render()
  }

  clear() {
    if (this.uploading) return
    this.items = []
    this.listTarget.replaceChildren()
    this.doneTarget.hidden = true
    this.overallTarget.hidden = true
    this.render()
  }

  // Uploading

  async start(event) {
    event.preventDefault()
    const pending = this.items.filter((item) => item.state === "queued")
    if (this.uploading || pending.length === 0) return

    this.uploading = true
    this.overallTarget.hidden = false
    this.doneTarget.hidden = true
    this.privateTarget.disabled = true
    pending.forEach((item) => this.field(item.row, "remove").hidden = true)
    this.render()

    const queue = [ ...pending ]
    const workers = Array.from({ length: Math.min(this.concurrencyValue, queue.length) }, async () => {
      while (queue.length) await this.upload(queue.shift())
    })
    await Promise.all(workers)

    this.uploading = false
    this.privateTarget.disabled = false
    this.finish()
  }

  upload(item) {
    return new Promise((resolve) => {
      const body = new FormData()
      body.append("files[]", item.file, item.file.name)
      if (this.privateTarget.checked) body.append("private", "1")

      const request = new XMLHttpRequest()
      request.open("POST", this.urlValue)
      request.setRequestHeader("Accept", "application/json")
      request.setRequestHeader("X-CSRF-Token", document.querySelector("meta[name=csrf-token]")?.content || "")
      request.upload.addEventListener("progress", (event) => {
        if (!event.lengthComputable) return
        item.loaded = event.loaded / event.total
        this.setRow(item, "uploading", `Uploading ${Math.round(item.loaded * 100)}%`, item.loaded)
      })
      request.addEventListener("load", () => {
        let result = null
        try { result = JSON.parse(request.responseText).results?.[0] } catch {}
        if (request.status >= 200 && request.status < 300 && result) {
          const states = { created: "done", duplicate: "skipped", unsupported: "skipped" }
          this.setRow(item, states[result.status] || "failed", result.status === "created" ? "Added. Processing has started." : result.message, 1, result)
        } else {
          this.setRow(item, "failed", `Upload failed (${request.status || "network error"})`, 1)
        }
        resolve()
      })
      request.addEventListener("error", () => { this.setRow(item, "failed", "Upload failed (network error)", 1); resolve() })
      this.setRow(item, "uploading", "Uploading 0%", 0)
      request.send(body)
    })
  }

  setRow(item, state, message, progress, result = null) {
    item.state = state
    item.loaded = progress
    item.result = result
    item.row.dataset.state = state
    this.field(item.row, "bar").style.width = `${Math.round(progress * 100)}%`
    this.field(item.row, "status").textContent = message
    if (result?.url) {
      const link = this.field(item.row, "link")
      link.href = result.url
      link.hidden = false
    }
    this.renderProgress()
  }

  finish() {
    const count = (state) => this.items.filter((item) => item.state === state).length
    const parts = [ `${count("done")} added` ]
    if (count("skipped")) parts.push(`${count("skipped")} skipped`)
    if (count("failed")) parts.push(`${count("failed")} failed`)
    this.doneSummaryTarget.textContent = parts.join(", ") + "."
    this.doneTarget.hidden = false
    this.render()
  }

  // Display

  render() {
    const queued = this.items.filter((item) => item.state === "queued")
    const bytes = queued.reduce((sum, item) => sum + item.file.size, 0)
    this.queueTarget.hidden = this.items.length === 0
    this.summaryTarget.textContent = this.uploading
      ? `Uploading ${this.items.filter((item) => item.state !== "queued" || item.loaded !== undefined).length} of ${this.items.length}`
      : queued.length
        ? `${queued.length} ${queued.length === 1 ? "file" : "files"} ready (${this.format(bytes)})`
        : `${this.items.length} ${this.items.length === 1 ? "file" : "files"}`
    this.submitTarget.disabled = this.uploading || queued.length === 0
    this.submitTarget.hidden = !this.uploading && queued.length === 0
    this.submitLabelTarget.textContent = queued.length > 1 ? `Upload ${queued.length} files` : "Upload"
    this.clearTarget.disabled = this.uploading
    this.renderProgress()
  }

  renderProgress() {
    const active = this.items.filter((item) => item.loaded !== undefined)
    if (active.length === 0) return
    const total = this.items.reduce((sum, item) => sum + item.file.size, 0) || 1
    const sent = active.reduce((sum, item) => sum + item.file.size * item.loaded, 0)
    this.overallBarTarget.style.width = `${Math.round((sent / total) * 100)}%`
  }

  field(row, name) {
    return row.querySelector(`[data-field="${name}"]`)
  }

  format(bytes) {
    if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`
  }
}
