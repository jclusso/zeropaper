import { Controller } from "@hotwired/stimulus"

// Calendar popover for shared/_date_picker. The partial owns the markup; this
// fills in the month grid from its <template>, keeps the hidden YYYY-MM-DD
// field and the friendly text field in step, and handles the keyboard.
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
const SHORT_MONTHS = MONTHS.map((month) => month.slice(0, 3))

export default class extends Controller {
  static targets = ["hidden", "input", "panel", "grid", "dayTemplate", "title", "clear"]
  static values = { clearable: Boolean, min: String, max: String }

  connect() {
    this.selected = parseISO(this.hiddenTarget.value)
    this.view = startOfMonth(this.selected || new Date())
    this.focused = this.selected || today()
    this.outside = (event) => { if (!this.element.contains(event.target) && !this.panelTarget.contains(event.target)) this.close() }
    this.reposition = () => this.position()
  }

  disconnect() {
    this.close()
  }

  // Opening and closing

  open() {
    if (this.isOpen) return
    this.view = startOfMonth(this.selected || today())
    this.focused = this.selected || today()
    this.render()
    this.panelTarget.showPopover()
    this.position()
    this.inputTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("pointerdown", this.outside)
    window.addEventListener("resize", this.reposition)
    window.addEventListener("scroll", this.reposition, true)
  }

  close({ focusInput = false } = {}) {
    if (!this.isOpen) return
    this.panelTarget.hidePopover()
    this.inputTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("pointerdown", this.outside)
    window.removeEventListener("resize", this.reposition)
    window.removeEventListener("scroll", this.reposition, true)
    if (focusInput) this.inputTarget.focus()
  }

  toggle() {
    if (this.isOpen) this.close({ focusInput: true })
    else { this.open(); this.focusDay() }
  }

  get isOpen() {
    return this.panelTarget.matches(":popover-open")
  }

  // Sits under the field in the top layer, so scrolling panels cannot clip it.
  position() {
    if (!this.isOpen) return
    const field = this.inputTarget.getBoundingClientRect()
    const panel = this.panelTarget.getBoundingClientRect()
    const below = field.bottom + 4
    const top = below + panel.height > window.innerHeight && field.top - panel.height - 4 > 0 ? field.top - panel.height - 4 : below
    const left = Math.max(8, Math.min(field.left, window.innerWidth - panel.width - 8))
    Object.assign(this.panelTarget.style, { top: `${top}px`, left: `${left}px` })
  }

  // Navigation

  previousMonth() { this.shiftView(-1) }
  nextMonth() { this.shiftView(1) }
  previousYear() { this.shiftView(-12) }
  nextYear() { this.shiftView(12) }

  shiftView(months) {
    this.view = addMonths(this.view, months)
    this.focused = clampToMonth(this.focused, this.view)
    this.render()
  }

  // Choosing

  pick(event) {
    this.choose(parseISO(event.currentTarget.dataset.date))
  }

  today() {
    this.choose(today())
  }

  clear() {
    this.set(null)
    this.close({ focusInput: true })
  }

  choose(date) {
    if (!date || this.outOfRange(date)) return
    this.set(date)
    this.close({ focusInput: true })
  }

  set(date) {
    const previous = this.hiddenTarget.value
    this.selected = date
    this.hiddenTarget.value = date ? toISO(date) : ""
    this.inputTarget.value = date ? friendly(date) : ""
    if (this.hasClearTarget) this.clearTarget.hidden = !(this.clearableValue && date)
    if (previous !== this.hiddenTarget.value) this.hiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // Typing a date

  inputKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.commitTyped()
      this.close()
    } else if (event.key === "ArrowDown" || (event.key === " " && event.altKey)) {
      event.preventDefault()
      this.open()
      this.focusDay()
    } else if (event.key === "Escape" && this.isOpen) {
      event.preventDefault()
      this.close()
    }
  }

  inputBlurred(event) {
    if (event.relatedTarget && this.panelTarget.contains(event.relatedTarget)) return
    this.commitTyped()
  }

  commitTyped() {
    const text = this.inputTarget.value.trim()
    if (text === "") {
      if (this.clearableValue) this.set(null)
      else this.inputTarget.value = this.selected ? friendly(this.selected) : ""
      return
    }

    const date = parseTyped(text)
    if (date && !this.outOfRange(date)) this.set(date)
    else this.inputTarget.value = this.selected ? friendly(this.selected) : ""
  }

  // Keyboard inside the calendar

  panelKeydown(event) {
    const moves = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }
    if (event.key in moves) {
      this.moveFocus(addDays(this.focused, moves[event.key]))
    } else if (event.key === "PageUp" || event.key === "PageDown") {
      const months = (event.key === "PageUp" ? -1 : 1) * (event.shiftKey ? 12 : 1)
      this.moveFocus(clampToMonth(this.focused, addMonths(startOfMonth(this.focused), months)))
    } else if (event.key === "Home") {
      this.moveFocus(addDays(this.focused, -this.focused.getDay()))
    } else if (event.key === "End") {
      this.moveFocus(addDays(this.focused, 6 - this.focused.getDay()))
    } else if ((event.key === "Enter" || event.key === " ") && event.target.dataset.date) {
      this.choose(parseISO(event.target.dataset.date))
    } else if (event.key === "Escape") {
      this.close({ focusInput: true })
    } else {
      return
    }
    event.preventDefault()
  }

  moveFocus(date) {
    this.focused = date
    if (date.getMonth() !== this.view.getMonth() || date.getFullYear() !== this.view.getFullYear()) {
      this.view = startOfMonth(date)
      this.render()
    }
    this.focusDay()
  }

  focusDay() {
    const day = this.gridTarget.querySelector(`[data-date="${toISO(this.focused)}"]`)
    this.gridTarget.querySelectorAll("[tabindex='0']").forEach((cell) => cell.setAttribute("tabindex", "-1"))
    if (day) { day.setAttribute("tabindex", "0"); day.focus() }
  }

  // Drawing the month

  render() {
    this.titleTarget.textContent = `${MONTHS[this.view.getMonth()]} ${this.view.getFullYear()}`
    const first = addDays(this.view, -this.view.getDay())
    const now = toISO(today())
    const chosen = this.selected && toISO(this.selected)
    const focused = toISO(this.focused)

    const cells = Array.from({ length: 42 }, (_, index) => {
      const date = addDays(first, index)
      const iso = toISO(date)
      const cell = this.dayTemplateTarget.content.firstElementChild.cloneNode(true)
      cell.textContent = date.getDate()
      cell.dataset.date = iso
      cell.setAttribute("aria-label", friendly(date))
      cell.setAttribute("aria-selected", String(iso === chosen))
      cell.setAttribute("tabindex", iso === focused ? "0" : "-1")
      if (date.getMonth() !== this.view.getMonth()) cell.dataset.outside = ""
      if (iso === now) cell.dataset.today = ""
      if (this.outOfRange(date)) cell.disabled = true
      return cell
    })
    this.gridTarget.replaceChildren(...cells)
    this.position()
  }

  outOfRange(date) {
    const iso = toISO(date)
    return (this.minValue && iso < this.minValue) || (this.maxValue && iso > this.maxValue)
  }
}

function today() {
  const now = new Date()
  return new Date(now.getFullYear(), now.getMonth(), now.getDate())
}

function startOfMonth(date) {
  return new Date(date.getFullYear(), date.getMonth(), 1)
}

function addDays(date, days) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days)
}

function addMonths(date, months) {
  return new Date(date.getFullYear(), date.getMonth() + months, 1)
}

// The same day number in another month, capped at that month's last day.
function clampToMonth(date, month) {
  const last = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
  return new Date(month.getFullYear(), month.getMonth(), Math.min(date.getDate(), last))
}

function toISO(date) {
  const pad = (number) => String(number).padStart(2, "0")
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

function friendly(date) {
  return `${SHORT_MONTHS[date.getMonth()]} ${date.getDate()}, ${date.getFullYear()}`
}

function build(year, month, day) {
  const date = new Date(year, month - 1, day)
  return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day ? date : null
}

function parseISO(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value || "")
  return match ? build(Number(match[1]), Number(match[2]), Number(match[3])) : null
}

function monthIndex(name) {
  const index = SHORT_MONTHS.findIndex((month) => month.toLowerCase() === name.slice(0, 3).toLowerCase())
  return index === -1 ? null : index + 1
}

// 2026-03-26, 3/26/2026, 3-26-2026, Mar 26 2026, March 26, 2026, 26 March 2026
function parseTyped(text) {
  let match
  if ((match = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(text))) return build(+match[1], +match[2], +match[3])
  if ((match = /^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$/.exec(text))) return build(+match[3], +match[1], +match[2])
  if ((match = /^([A-Za-z]{3,})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})$/.exec(text))) {
    const month = monthIndex(match[1])
    return month && build(+match[3], month, +match[2])
  }
  if ((match = /^(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,})\.?,?\s+(\d{4})$/.exec(text))) {
    const month = monthIndex(match[2])
    return month && build(+match[3], month, +match[1])
  }
  return null
}
