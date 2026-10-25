// Light or dark theme. Follows the system until a visitor picks one with the
// header toggle, and remembers that choice in this browser. Loaded without
// defer in <head> so the page never flashes the wrong theme.
(function () {
  var system = matchMedia("(prefers-color-scheme: dark)")
  var root = document.documentElement
  var chosen = null

  try { chosen = localStorage.getItem("theme") } catch (e) {}

  function isDark() { return chosen ? chosen === "dark" : system.matches }

  function apply() {
    var dark = isDark()
    root.classList.toggle("dark", dark)
    root.style.colorScheme = dark ? "dark" : "light"
    // Screenshots swap to their dark versions with the theme, not only the system's.
    Array.prototype.forEach.call(document.querySelectorAll("source[data-dark]"), function (source) {
      source.media = dark ? "all" : "not all"
    })
    var toggle = document.querySelector(".theme-toggle")
    if (toggle) toggle.setAttribute("aria-label", dark ? "Switch to light mode" : "Switch to dark mode")
  }

  apply()
  system.addEventListener("change", apply)

  document.addEventListener("DOMContentLoaded", function () {
    var toggle = document.querySelector(".theme-toggle")
    toggle.hidden = false
    toggle.addEventListener("click", function () {
      chosen = isDark() ? "light" : "dark"
      try {
        // Picking the system's own theme goes back to following the system.
        if (chosen === (system.matches ? "dark" : "light")) {
          localStorage.removeItem("theme")
        } else {
          localStorage.setItem("theme", chosen)
        }
      } catch (e) {}
      apply()
    })
    apply()
  })
})()
