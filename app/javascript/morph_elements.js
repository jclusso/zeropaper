// Turbo morphs the page on refreshes and on same-page "replace" visits, such
// as the filter bar submitting. Morphing keeps a Tailwind Plus element but
// swaps its children, leaving it pointing at nodes that are gone, so menus
// stop opening. Afterwards each one is replaced with a fresh copy, except one
// being used (focused or open), so a live update never interrupts typing.
//
// One being used is not morphed at all. The new HTML has no `open` attribute,
// and stripping it from an open modal <dialog> hides it while it stays modal,
// so nothing on the page can be clicked.
const ELEMENTS = "el-select, el-autocomplete, el-dropdown, el-popover, el-dialog"

function inUse(element) {
  return element.contains(document.activeElement) || element.matches(":popover-open") || !!element.querySelector(":popover-open, dialog[open]")
}

document.addEventListener("turbo:before-morph-element", (event) => {
  if (event.target.matches(ELEMENTS) && inUse(event.target)) event.preventDefault()
})

document.addEventListener("turbo:morph", () => {
  document.querySelectorAll(ELEMENTS).forEach((element) => {
    if (element.parentElement?.closest(ELEMENTS) || inUse(element)) return
    element.replaceWith(element.cloneNode(true))
  })
})
