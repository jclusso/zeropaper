// The site's small scripts: the Research, search and inbox demos, the hero's
// rotating word and the Quick start copy buttons.
//
// Each demo's markup is a finished screen, so without JavaScript, or with
// reduced motion, it shows as it is. Otherwise every demo is put into its
// starting state as soon as this script runs, long before it scrolls into
// view, and plays once it does; Replay starts it over. Starting states keep
// the demo's size, so nothing on the page moves.
(function () {
  "use strict"

  var reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)")

  // Resolves after ms, or rejects when a newer play has started.
  function pause(run, ms) {
    return new Promise(function (resolve, reject) {
      setTimeout(function () { run.current() ? resolve() : reject(new Error("replaced")) }, ms)
    })
  }

  function all(root, selector) { return Array.prototype.slice.call(root.querySelectorAll(selector)) }
  function hide(element) { element.classList.add("is-hidden") }
  function show(element) { element.classList.remove("is-hidden") }
  function parts(demo, name) { return all(demo, '[data-part="' + name + '"]') }

  // Wraps every word of the answer in a span, once, so it can stream in
  // word by word without the text reflowing. A citation marker is one word.
  function wrapWords(container) {
    if (container.dataset.wrapped) return
    container.dataset.wrapped = "true"
    var walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT)
    var nodes = []
    while (walker.nextNode()) nodes.push(walker.currentNode)
    nodes.forEach(function (node) {
      if (node.parentElement.classList.contains("citation-marker")) {
        node.parentElement.classList.add("word")
        return
      }
      var fragment = document.createDocumentFragment()
      node.textContent.split(/(\s+)/).forEach(function (piece) {
        if (!piece) return
        if (/^\s+$/.test(piece)) {
          fragment.appendChild(document.createTextNode(piece))
        } else {
          var word = document.createElement("span")
          word.className = "word"
          word.textContent = piece
          fragment.appendChild(word)
        }
      })
      node.parentNode.replaceChild(fragment, node)
    })
  }

  function setStepIcon(step, icon) {
    step.querySelector("use").setAttribute("href", icon)
  }

  // Research: the question, then each step, then the answer word by word.
  var research = {
    prepare: function (demo) {
      var steps = parts(demo, "steps")[0]
      var answer = parts(demo, "answer")[0]
      wrapWords(answer)
      ;[ parts(demo, "question")[0], steps, answer ].concat(parts(demo, "sources"), parts(demo, "private"), all(answer, ".word")).forEach(hide)
      steps.querySelector(".step-summary").classList.add("invisible")
      steps.querySelector(".step-list").hidden = false
      all(steps, ".step-list li").forEach(function (item) { item.hidden = true })
    },

    play: async function (demo, run) {
      var steps = parts(demo, "steps")[0]
      var answer = parts(demo, "answer")[0]
      var later = parts(demo, "sources").concat(parts(demo, "private"))
      var list = steps.querySelector(".step-list")
      var items = all(list, "li")
      var words = all(answer, ".word")

      await pause(run, 300)
      show(parts(demo, "question")[0])
      await pause(run, 700)
      show(steps)
      for (var i = 0; i < items.length; i++) {
        var item = items[i]
        var icon = item.querySelector("svg")
        var label = item.querySelector("span")
        item.hidden = false
        setStepIcon(item, "#i-refresh")
        icon.classList.add("animate-spin", "text-strong-accent")
        label.classList.add("shimmer")
        await pause(run, 750)
        setStepIcon(item, "#i-check")
        icon.classList.remove("animate-spin", "text-strong-accent")
        label.classList.remove("shimmer")
      }
      await pause(run, 500)
      list.hidden = true
      steps.querySelector(".step-summary").classList.remove("invisible")
      show(answer)
      for (var w = 0; w < words.length; w++) {
        show(words[w])
        await pause(run, 38)
      }
      for (var p = 0; p < later.length; p++) {
        await pause(run, 350)
        show(later[p])
      }
    }
  }

  // Search: the query is typed, its filters fill in, then the results.
  var QUERY = "insurance from Harbor Mutual 2026"
  var search = {
    prepare: function (demo) {
      var typed = demo.querySelector(".typed")
      typed.dataset.final = typed.dataset.final || typed.textContent
      typed.textContent = ""
      all(demo, "[data-filter]").forEach(function (filter) {
        var value = filter.querySelector(".value")
        value.dataset.final = value.dataset.final || value.textContent
        value.textContent = filter.dataset.empty
        value.classList.add("muted")
        filter.classList.remove("is-filled")
      })
      parts(demo, "count").concat(parts(demo, "result")).forEach(hide)
    },

    play: async function (demo, run) {
      var typed = demo.querySelector(".typed")
      var filters = all(demo, "[data-filter]")
      var later = parts(demo, "count").concat(parts(demo, "result"))

      demo.classList.add("is-typing")
      await pause(run, 500)
      for (var i = 1; i <= QUERY.length; i++) {
        typed.textContent = QUERY.slice(0, i)
        typed.scrollLeft = typed.scrollWidth
        await pause(run, 55)
      }
      await pause(run, 600)
      typed.innerHTML = 'insurance <span class="chip">from Harbor Mutual</span> <span class="chip">2026</span>'
      typed.scrollLeft = typed.scrollWidth
      await pause(run, 700)
      all(typed, ".chip").forEach(function (chip) { chip.classList.add("is-gone") })
      await pause(run, 400)
      typed.textContent = typed.dataset.final
      typed.scrollLeft = 0
      demo.classList.remove("is-typing")

      for (var f = 0; f < filters.length; f++) {
        var value = filters[f].querySelector(".value")
        value.textContent = value.dataset.final
        value.classList.remove("muted")
        filters[f].classList.add("is-filled")
        await pause(run, 300)
      }
      await pause(run, 300)
      for (var l = 0; l < later.length; l++) {
        show(later[l])
        await pause(run, 220)
      }
      await pause(run, 600)
      filters.forEach(function (filter) { filter.classList.remove("is-filled") })
    }
  }

  // Inbox: items are cleared one by one with their own action; the rest
  // slide up and the next ones come into view from below. The list keeps
  // the height of the first five items, as in the finished screen.
  var VISIBLE_ITEMS = 5
  var FOLD = [ "height", "marginBottom", "paddingTop", "paddingBottom", "borderWidth" ]

  function fitInbox(demo) {
    var list = demo.querySelector(".inbox-list")
    var items = all(list, "[data-item]").filter(function (item) { return !item.hidden && !item.classList.contains("is-leaving") })
    var next = items[VISIBLE_ITEMS]
    if (!next) return
    // Up to the next item, so the gap after the fifth stays as in the static list.
    list.style.height = (next.offsetTop - items[0].offsetTop) + "px"
  }

  function setCount(demo, count) {
    var counter = demo.querySelector("[data-count]")
    if (counter) counter.textContent = count
  }

  var inbox = {
    prepare: function (demo) {
      var list = demo.querySelector(".inbox-list")
      var items = all(list, "[data-item]")
      list.style.position = "relative"
      list.style.overflow = "hidden"
      items.forEach(function (item) {
        item.classList.remove("is-leaving")
        FOLD.forEach(function (property) { item.style[property] = "" })
        item.hidden = false
        var button = item.querySelector("[data-press]")
        if (button) button.classList.remove("is-pressed")
      })
      // Every item stays in the list; the ones past the fifth wait below its edge.
      fitInbox(demo)
      setCount(demo, items.length)
    },

    play: async function (demo, run) {
      var list = demo.querySelector(".inbox-list")
      var count = all(list, "[data-item]").length
      var cleared = all(list, "[data-item][data-clear]")

      await pause(run, 900)
      for (var i = 0; i < cleared.length; i++) {
        var item = cleared[i]
        var button = item.querySelector("[data-press]")
        button.classList.add("is-pressed")
        await pause(run, 220)
        button.classList.remove("is-pressed")
        await pause(run, 250)
        // Fix the height first so it can shrink to nothing; the items below slide up.
        item.style.height = item.offsetHeight + "px"
        void item.offsetHeight
        item.classList.add("is-leaving")
        FOLD.forEach(function (property) { item.style[property] = "0" })
        setCount(demo, --count)
        await pause(run, 700)
        item.hidden = true
        await pause(run, 450)
      }
    }
  }

  var players = { research: research, search: search, inbox: inbox }

  function setUp(demo) {
    var player = players[demo.dataset.demo]
    var replay = demo.querySelector(".replay")
    var latest = 0

    function start() {
      var id = ++latest
      var run = { current: function () { return id === latest } }
      replay.hidden = true
      player.prepare(demo)
      player.play(demo, run).then(function () { replay.hidden = false }, function () {})
    }

    // The starting state now, so the finished screen never shows and then vanishes.
    player.prepare(demo)
    replay.addEventListener("click", start)

    var observer = new IntersectionObserver(function (entries) {
      if (entries.some(function (entry) { return entry.isIntersecting })) {
        observer.disconnect()
        start()
      }
    }, { threshold: 0.35 })
    observer.observe(demo)

    if (demo.dataset.demo === "inbox") {
      window.addEventListener("resize", function () { fitInbox(demo) })
    }
  }

  // The hero's accented word cycles while the hero is on screen and the tab
  // is visible. Screen readers and the static page read "searchable". The
  // slot eases to the width of the current word, so the words after it stay
  // a space away.
  function rotateHeroWord() {
    var slot = document.querySelector(".rotator-words")
    if (!slot) return
    var words = all(slot, "span")
    var index = 0
    var timer = null
    var onScreen = true

    function step() {
      var current = words[index]
      index = (index + 1) % words.length
      current.classList.remove("is-current")
      current.classList.add("is-out")
      words[index].classList.remove("is-out")
      words[index].classList.add("is-current")
      fit()
      setTimeout(function () { current.classList.remove("is-out") }, 450)
    }

    function fit() {
      slot.style.width = words[index].offsetWidth + "px"
    }

    function update() {
      var running = onScreen && !document.hidden
      if (running && !timer) timer = setInterval(step, 2500)
      if (!running && timer) { clearInterval(timer); timer = null }
    }

    new IntersectionObserver(function (entries) {
      onScreen = entries[entries.length - 1].isIntersecting
      update()
    }).observe(slot)
    document.addEventListener("visibilitychange", update)
    window.addEventListener("resize", fit)
  }

  // Copies the Quick start commands, without the comment lines.
  function setUpCopyButtons() {
    if (!navigator.clipboard) return
    all(document, "[data-copy] .copy").forEach(function (button) {
      var label = button.querySelector("span")
      var code = button.closest("[data-copy]").querySelector("code")
      var reset = null
      button.hidden = false
      button.addEventListener("click", function () {
        var commands = code.textContent.split("\n").filter(function (line) { return line.trim() && !/^\s*#/.test(line) }).join("\n") + "\n"
        navigator.clipboard.writeText(commands).then(function () {
          label.textContent = "Copied"
          button.classList.add("is-copied")
          clearTimeout(reset)
          reset = setTimeout(function () {
            label.textContent = "Copy"
            button.classList.remove("is-copied")
          }, 1600)
        }, function () {})
      })
    })
  }

  function init() {
    setUpCopyButtons()
    if (reducedMotion.matches || !("IntersectionObserver" in window)) return
    all(document, "[data-demo]").forEach(setUp)
    rotateHeroWord()
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init)
  } else {
    init()
  }
})()
